// File-based storage for the outbox queue, one JSON file per job for memory efficiency.
// Files are named by an enqueue sequence, so delivery order is enqueue order.

import Foundation

// MARK: - Outbox Storage

/// File-based storage for outbox jobs, named by sequence and UUID so delivery order is enqueue order.
/// Eviction enforces the job count and age limits.
internal final class OutboxStorage: @unchecked Sendable {
    
    // MARK: - Configuration
    
    /// Maximum number of jobs to retain (FIFO eviction beyond this)
    private let maxJobCount: Int
    
    /// Maximum age for jobs (older jobs are evicted)
    private let maxJobAge: TimeInterval
    
    // MARK: - Properties
    
    private let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let queue: DispatchQueue
    /// Serializes numbering and writing across EVERY instance: the configured
    /// outbox and `UnconfiguredOutbox` each hold one on the same directory, on
    /// their own queues.
    private static let writeLock = NSLock()
    
    // MARK: - Init
    
    init(
        maxJobCount: Int = 100,
        maxJobAge: TimeInterval = 7 * 24 * 60 * 60, // 7 days
        directory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.maxJobCount = maxJobCount
        self.maxJobAge = maxJobAge
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.queue = DispatchQueue(label: "com.encore.outbox.storage", qos: .utility)
        
        // Use provided directory or default to App Support
        if let directory {
            self.directory = directory
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directory = appSupport.appendingPathComponent("com.encore.sdk/outbox", isDirectory: true)
        }
        
        ensureDirectoryExists()
        queue.sync {
            Self.writeLock.lock()
            defer { Self.writeLock.unlock() }
            moveHandshakesFirst()
        }
        Logger.debug("OutboxStorage: Initialized at: \(self.directory.path)")
    }
    
    // MARK: - Public API
    
    /// Enqueue a new job. Automatically trims old jobs if over limit.
    /// - Returns: `true` if job was persisted successfully, `false` otherwise.
    @discardableResult
    func enqueue(_ job: OutboxJob) -> Bool {
        queue.sync {
            Self.writeLock.lock()
            defer { Self.writeLock.unlock() }
            ensureDirectoryExists()
            // sequence-uuid.json. The sequence is the creation millisecond, but
            // never at or below the last one handed out, so neither a job
            // created in the same millisecond nor a clock moved back can sort
            // an identify alias ahead of the handshake that creates its user.
            let sequence = nextSequence(after: Int64(job.createdAt.timeIntervalSince1970 * 1000))
            let filename = "\(sequence)-\(job.id).json"
            let fileURL = directory.appendingPathComponent(filename)
            
            // Write atomically (temp file + move)
            do {
                let data = try encoder.encode(job)
                try data.write(to: fileURL, options: .atomic)
                Logger.debug("OutboxStorage: Enqueued job: \(job.id)")
            } catch {
                // Disk failures are critical for data integrity, so the first of each kind
                // is reported. The rest of the burst logs as a warning.
                Self.reportWriteFailure(error)
                return false
            }

            // Evict old jobs to stay within limits
            trim()
            return true
        }
    }
    
    /// Peek at the next job without removing it.
    func peek() -> OutboxJob? {
        queue.sync {
            guard let filename = sortedFilenames().first else { return nil }
            return loadJob(filename: filename)
        }
    }
    
    /// Remove a job by ID (called after successful processing).
    func remove(jobId: String) {
        queue.sync {
            guard let filename = sortedFilenames().first(where: { $0.contains(jobId) }) else { return }
            let fileURL = directory.appendingPathComponent(filename)
            try? fileManager.removeItem(at: fileURL)
            Logger.debug("OutboxStorage: Removed job: \(jobId)")
        }
    }
    
    /// Update a job (e.g., increment attempt count, store error).
    /// - Returns: `true` if job was updated successfully, `false` otherwise.
    @discardableResult
    func update(_ job: OutboxJob) -> Bool {
        queue.sync {
            guard let filename = sortedFilenames().first(where: { $0.contains(job.id) }) else { return false }
            let fileURL = directory.appendingPathComponent(filename)

            do {
                let data = try encoder.encode(job)
                try data.write(to: fileURL, options: .atomic)
                return true
            } catch {
                // Update failures could lead to stuck jobs, so the first of each kind is
                // reported. A full disk fails this write for every job in the queue.
                Self.reportWriteFailure(error)
                return false
            }
        }
    }
    
    /// Get the count of pending jobs.
    var count: Int {
        queue.sync {
            sortedFilenames().count
        }
    }
    
    /// Get all pending jobs (for debugging/monitoring).
    func allJobs() -> [OutboxJob] {
        queue.sync {
            sortedFilenames().compactMap { loadJob(filename: $0) }
        }
    }
    
    // MARK: - Private Helpers

    /// A failed enqueue drops the job; a failed update leaves it on disk with its old attempt count.
    private static func reportWriteFailure(_ error: Error, file: String = #file, line: Int = #line, function: String = #function) {
        PersistenceFailureReporter.report(error, context: .outbox, source: "OutboxStorage", file: file, line: line, function: function)
    }

    /// Recreates the outbox directory if the OS removed it since init. It keeps the host app's
    /// protection class: the outbox holds identify payloads, so it never lowers that choice.
    private func ensureDirectoryExists() {
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// Job filenames in enqueue order: by numeric sequence prefix, then name.
    /// Files written before the sequence carry their creation millisecond in
    /// the same place, so they keep their order.
    private func sortedFilenames() -> [String] {
        let contents = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return contents.filter { $0.hasSuffix(".json") }.sorted { a, b in
            let (sa, sb) = (Self.sequence(of: a), Self.sequence(of: b))
            return sa != sb ? sa < sb : a < b
        }
    }

    /// Continues after the newest job on disk, read fresh each time so another
    /// instance's jobs and a restart both count.
    private func nextSequence(after candidate: Int64) -> Int64 {
        guard let last = sortedFilenames().last.map(Self.sequence(of:)) else { return candidate }
        return max(candidate, last + 1)
    }

    private static func sequence(of filename: String) -> Int64 {
        Int64(filename.prefix { $0 != "-" }) ?? 0
    }
    
    /// Repairs a queue an older build saved, where an identify could sort ahead of the handshake that creates
    /// its user: each `POST /users` moves to just before the first earlier identify from its user. Nothing
    /// else moves. Android's `handshakesFirst`, stateless and run on every open.
    private func moveHandshakesFirst() {
        let filenames = sortedFilenames()
        let jobs = filenames.map(loadJob(filename:))
        let inits = jobs.map { $0.flatMap { $0.request.path == "users" && $0.request.method == "POST" ? Self.bodyField("userId", of: $0) : nil } }
        let aliasFrom = jobs.map { $0.flatMap { $0.request.path == "users/identify" ? Self.bodyField("currentUserId", of: $0) : nil } }
        var ordered = Array(filenames.indices)
        for index in filenames.indices {
            guard let userId = inits[index],
                  let alias = ordered.firstIndex(where: { aliasFrom[$0] == userId }),
                  let position = ordered.firstIndex(of: index), alias < position else { continue }
            ordered.remove(at: position)
            ordered.insert(index, at: alias)
        }
        guard ordered != Array(filenames.indices), let head = filenames.first.map(Self.sequence(of:)),
              head > Int64(filenames.count) else { return }
        // Renumbered below the current head, so no new name collides with one on disk.
        for (offset, index) in ordered.enumerated() {
            let name = filenames[index]
            let renamed = "\(head - Int64(filenames.count - offset))\(name.drop { $0 != "-" })"
            do {
                try fileManager.moveItem(at: directory.appendingPathComponent(name), to: directory.appendingPathComponent(renamed))
            } catch {
                // That job keeps its old number and sorts after the renumbered jobs.
                Logger.warn("OutboxStorage: could not reorder \(name): \(error)")
            }
        }
    }

    private static func bodyField(_ name: String, of job: OutboxJob) -> String? {
        guard let body = job.request.body, let dict = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        return dict[name] as? String
    }

    /// Load a job from a file.
    private func loadJob(filename: String) -> OutboxJob? {
        let fileURL = directory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(OutboxJob.self, from: data)
    }
    
    /// Evict jobs that exceed count or age limits.
    private func trim() {
        let filenames = sortedFilenames()
        let now = Date()
        
        for (index, filename) in filenames.enumerated() {
            let fileURL = directory.appendingPathComponent(filename)
            var shouldRemove = false
            
            // Remove if over count limit (keep newest, remove oldest)
            if index < filenames.count - maxJobCount {
                shouldRemove = true
                Logger.debug("OutboxStorage: Evicting job (count limit): \(filename)")
            }
            
            // Remove if too old
            if let job = loadJob(filename: filename), now.timeIntervalSince(job.createdAt) > maxJobAge {
                shouldRemove = true
                Logger.debug("OutboxStorage: Evicting job (age limit): \(filename)")
            }
            
            if shouldRemove {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }
}
