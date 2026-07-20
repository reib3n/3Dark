import CryptoKit
import Foundation

/// Finds models that share identical 3D files, by content hash.
///
/// Hashing is never done in the background — it runs on import (where
/// the files are being touched anyway) and on explicit request. Hashes
/// are cached per path + size + modification date, so repeat scans of an
/// unchanged archive are cheap even on network/cloud volumes.
actor DuplicateFinder {
    static let shared = DuplicateFinder()

    struct DuplicateGroup: Identifiable {
        let hash: String
        let models: [Model3D]
        var id: String { hash }
    }

    struct ScanResult {
        var groups: [DuplicateGroup] = []
        /// Files hashed from scratch in this run (cold cache).
        var hashedFiles = 0
        /// Files served from the cache (unchanged since a prior scan).
        var cachedFiles = 0
        var totalFiles: Int { hashedFiles + cachedFiles }
    }

    private struct CacheKey: Hashable {
        let path: String
        let size: Int
        let modified: Date
    }

    /// One persisted cache entry. Size and mtime travel with the hash so
    /// a changed file is detected instead of served stale.
    private struct CacheEntry: Codable {
        let path: String
        let size: Int
        let modified: Date
        let hash: String
    }

    private var cache: [CacheKey: String] = [:]
    private var cacheLoaded = false
    private var cacheDirty = false
    private var runHashed = 0
    private var runCached = 0

    /// Derived data — deliberately stored outside the archive: keeps
    /// model.md human-readable and avoids sync traffic on cloud volumes.
    private static var cacheFileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folder = base.appendingPathComponent("3Dark", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("hash-cache.json")
    }

    private func loadCacheIfNeeded() {
        guard !cacheLoaded else { return }
        cacheLoaded = true
        guard let url = Self.cacheFileURL,
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([CacheEntry].self, from: data) else {
            return
        }
        for entry in entries {
            cache[CacheKey(path: entry.path, size: entry.size, modified: entry.modified)] = entry.hash
        }
    }

    /// Persists the cache, dropping entries whose file no longer exists
    /// so the file doesn't grow forever.
    private func persistCache() {
        guard cacheDirty, let url = Self.cacheFileURL else { return }
        cacheDirty = false
        let entries = cache
            .filter { FileManager.default.fileExists(atPath: $0.key.path) }
            .map { CacheEntry(path: $0.key.path, size: $0.key.size, modified: $0.key.modified, hash: $0.value) }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Full scan: every 3D file of every model is hashed. Files not yet
    /// in the cache — i.e. the entire existing archive on a first run —
    /// are hashed from scratch here. `progress` reports scanned models.
    func scan(models: [Model3D], progress: (@Sendable (Int) -> Void)? = nil) -> ScanResult {
        loadCacheIfNeeded()
        runHashed = 0
        runCached = 0
        var byHash: [String: [Model3D]] = [:]
        for (index, model) in models.enumerated() {
            for hash in hashes(for: model) {
                // A model appears once per hash, even with duplicate
                // files inside its own folder.
                if byHash[hash]?.contains(where: { $0.id == model.id }) != true {
                    byHash[hash, default: []].append(model)
                }
            }
            progress?(index + 1)
        }
        let groups = byHash
            .filter { $0.value.count > 1 }
            .map { DuplicateGroup(hash: $0.key, models: $0.value.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) }
            .sorted { $0.models[0].title.localizedStandardCompare($1.models[0].title) == .orderedAscending }
        persistCache()
        return ScanResult(groups: groups, hashedFiles: runHashed, cachedFiles: runCached)
    }

    /// Existing models that share a 3D file with `candidate`.
    func duplicates(of candidate: Model3D, in models: [Model3D]) -> [Model3D] {
        loadCacheIfNeeded()
        let candidateHashes = Set(hashes(for: candidate))
        guard !candidateHashes.isEmpty else {
            persistCache()
            return []
        }
        let matches = models.filter { other in
            guard other.id != candidate.id else { return false }
            return hashes(for: other).contains { candidateHashes.contains($0) }
        }
        persistCache()
        return matches
    }

    func hashes(for model: Model3D) -> [String] {
        model.files3D.compactMap { hash(of: $0) }
    }

    /// SHA-256 of a file, streamed in chunks so large STLs don't get
    /// loaded into memory.
    private func hash(of url: URL) -> String? {
        // FileManager attributes instead of URL.resourceValues: the
        // latter caches values on the URL object, which would produce a
        // stale cache key (and thus a stale hash) for a changed file.
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let key = CacheKey(
            path: url.path,
            size: (attributes?[.size] as? NSNumber)?.intValue ?? -1,
            modified: attributes?[.modificationDate] as? Date ?? .distantPast
        )
        if let cached = cache[key] {
            runCached += 1
            return cached
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        cache[key] = digest
        cacheDirty = true
        runHashed += 1
        return digest
    }
}
