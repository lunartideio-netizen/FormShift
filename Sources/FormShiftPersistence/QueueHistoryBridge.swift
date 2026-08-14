import Foundation
import FormShiftCore

public actor QueueHistoryBridge {
    private let queue: ConversionQueue
    private let persistence: PersistenceController
    private var observationTask: Task<Void, Never>?
    private var lastSavedSignature: [UUID: String] = [:]

    public init(queue: ConversionQueue, persistence: PersistenceController) {
        self.queue = queue
        self.persistence = persistence
    }

    deinit {
        observationTask?.cancel()
    }

    public func start() {
        guard observationTask == nil else { return }
        observationTask = Task { [weak self, queue] in
            let updates = await queue.updates()
            for await jobs in updates {
                guard !Task.isCancelled else { break }
                await self?.record(jobs)
            }
        }
    }

    public func stop() {
        observationTask?.cancel()
        observationTask = nil
    }

    private func record(_ jobs: [ConversionJob]) async {
        for job in jobs {
            let signature = "\(job.status.rawValue):\(job.progress):\(job.statusDetail ?? "")"
            guard lastSavedSignature[job.id] != signature else { continue }
            do {
                try await persistence.upsert(job: job)
                lastSavedSignature[job.id] = signature
            } catch {
                // Persistence failures must never stop or corrupt an active conversion.
            }
        }
    }
}
