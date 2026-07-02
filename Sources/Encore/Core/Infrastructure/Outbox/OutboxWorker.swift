// Sources/Encore/Core/Infrastructure/Outbox/OutboxWorker.swift
//
// Background worker that processes the outbox queue.
// Implements exponential backoff with jitter for retries.

import Foundation

// MARK: - Outbox Worker

/// Background worker that processes outbox jobs.
/// - Runs continuously while jobs exist
/// - Implements exponential backoff with jitter
/// - Respects network reachability (future enhancement)
internal final class OutboxWorker: @unchecked Sendable {
    
    // MARK: - Configuration
    
    /// Maximum number of retry attempts before giving up on a job
    private let maxAttempts: Int
    
    /// Base delay for exponential backoff (in seconds)
    private let baseDelay: TimeInterval
    
    /// Maximum delay cap (in seconds)
    private let maxDelay: TimeInterval
    
    // MARK: - Properties
    
    private let storage: OutboxStorage
    private let clients: [ClientTarget: HTTPClientProtocol]
    private var isRunning: Bool = false
    private var processingTask: Task<Void, Never>?
    private let lock = NSLock()
    
    // MARK: - Init
    
    init(
        storage: OutboxStorage,
        clients: [ClientTarget: HTTPClientProtocol],
        maxAttempts: Int = 3,
        baseDelay: TimeInterval = 2.0,
        maxDelay: TimeInterval = 16.0
    ) {
        self.storage = storage
        self.clients = clients
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }
    
    // MARK: - Public API
    
    /// Start the worker (idempotent - safe to call multiple times).
    func start() {
        lock.lock()
        defer { lock.unlock() }
        
        guard !isRunning else { return }
        isRunning = true
        
        processingTask = Task.detached(priority: .utility) { [weak self] in
            await self?.processLoop()
        }
        
        Logger.debug("▶️ [OutboxWorker] Started")
    }
    
    /// Stop the worker.
    func stop() {
        lock.lock()
        defer { lock.unlock() }
        
        isRunning = false
        processingTask?.cancel()
        processingTask = nil
        
        Logger.debug("⏹️ [OutboxWorker] Stopped")
    }
    
    /// Trigger immediate processing (e.g., when network becomes available).
    func processNow() {
        start() // Idempotent - just ensures we're running
    }
    
    // MARK: - Processing Loop
    
    private func processLoop() async {
        while isRunning {
            // Check for a job
            guard var job = storage.peek() else {
                // No jobs - wait and check again
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                continue
            }
            
            // Check if job has exceeded max attempts
            if job.attemptCount >= maxAttempts {
                Logger.warn("⚠️ [OutboxWorker] Job \(job.id) exceeded max attempts, removing")
                storage.remove(jobId: job.id)
                continue
            }
            
            // Attempt to process the job
            job.attemptCount += 1
            
            do {
                try await execute(job)
                storage.remove(jobId: job.id)
                Logger.info("✅ [OutboxWorker] Job \(job.id) completed successfully")
            } catch {
                // Update job with error and retry later
                job.lastError = error.localizedDescription
                storage.update(job)
                
                // Calculate backoff delay with jitter
                let delay = calculateBackoff(attempt: job.attemptCount)
                Logger.warn("⚠️ [OutboxWorker] Job \(job.id) failed (attempt \(job.attemptCount)), retrying in \(Int(delay))s: \(error.localizedDescription)")
                
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }
    
    // MARK: - Request Execution
    
    private func execute(_ job: OutboxJob) async throws {
        guard let client = clients[job.clientTarget] else {
            Logger.warn("⚠️ [OutboxWorker] No client for target: \(job.clientTarget.rawValue), dropping job \(job.id)")
            return
        }
        
        let query: [String: String?]? = job.request.query?.mapValues { Optional($0) }
        
        // Execute request with pre-serialized body (no decode/re-encode)
        let _: EmptyResponse = try await client.request(
            path: job.request.path,
            method: job.request.method,
            bodyData: job.request.body,
            query: query
        )
    }
    
    // MARK: - Backoff Calculation
    
    /// Calculate exponential backoff with jitter.
    /// Formula: min(maxDelay, baseDelay * 2^attempt) + random jitter
    private func calculateBackoff(attempt: Int) -> TimeInterval {
        let exponential = baseDelay * pow(2.0, Double(attempt - 1))
        let capped = min(exponential, maxDelay)
        let jitter = Double.random(in: 0...(capped * 0.1)) // 10% jitter
        return capped + jitter
    }
}

