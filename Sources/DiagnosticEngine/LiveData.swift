import Foundation
import OBDCore

extension DiagnosticSession {
    /// Polls the given OBD PIDs in a loop. Each cycle reads every PID once, then waits for the rest of `interval`.
    public nonisolated func live(pids: [UInt8], interval: Duration = .milliseconds(500)) -> AsyncThrowingStream<MeasurementRecord, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.runLive(pids: pids, interval: interval) { continuation.yield($0) }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch OBDError.cancelled {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func runLive(pids: [UInt8], interval: Duration, emit: @Sendable (MeasurementRecord) -> Void) async throws {
        try await exclusive("Live-Daten") {
            try await ensureConnected()
            try await driver.selectBus(.hsCAN)
            let obd = OBDService(driver: driver)
            while true {
                try Task.checkCancellation()
                let started = ContinuousClock.now
                for pid in pids {
                    for record in try await obd.readPID(pid) {
                        emit(record)
                    }
                }
                let elapsed = ContinuousClock.now - started
                if elapsed < interval {
                    try await Task.sleep(for: interval - elapsed)
                }
            }
        }
    }
}
