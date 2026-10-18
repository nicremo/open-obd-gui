import Darwin
import Foundation
import Testing
import OBDCore
@testable import AdapterKit

/// Plays the adapter on the master side of a pseudo terminal.
final class FakeAdapter: @unchecked Sendable {
    let master: Int32
    let path: String

    init() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0, let name = ttyname(slave) else {
            throw OBDError.io("openpty fehlgeschlagen")
        }
        self.master = master
        path = String(cString: name)
        Darwin.close(slave)
    }

    deinit { Darwin.close(master) }

    /// Reads one CR terminated command, or nil after `timeout`.
    func readCommand(timeout: Duration = .seconds(2)) -> String? {
        var buffer: [UInt8] = []
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            var descriptor = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 20) > 0 else { continue }
            var byte: UInt8 = 0
            guard Darwin.read(master, &byte, 1) == 1 else { return nil }
            if byte == 0x0D { return String(decoding: buffer, as: UTF8.self) }
            buffer.append(byte)
        }
        return nil
    }

    func send(_ text: String) {
        let bytes = Array(text.utf8)
        _ = bytes.withUnsafeBytes { Darwin.write(master, $0.baseAddress, $0.count) }
    }

    /// Answers commands on a background thread until `handler` returns nil.
    func serve(_ handler: @escaping @Sendable (String) -> [String]?) {
        DispatchQueue.global().async {
            while let command = self.readCommand(timeout: .seconds(5)), let pieces = handler(command) {
                for piece in pieces {
                    self.send(piece)
                    usleep(15_000)
                }
            }
        }
    }
}

@Suite(.serialized) struct SerialLinkTests {
    @Test func exchangesCommandAndPrompt() async throws {
        let fake = try FakeAdapter()
        let link = try SerialLink.open(path: fake.path)
        fake.serve { command in command == "ATI" ? ["ELM327 v1.4b\r\r>"] : nil }
        let reply = try await link.transact("ATI", timeout: .seconds(2))
        #expect(reply.text == "ELM327 v1.4b\r\r")
        await link.close()
    }

    @Test func reassemblesFragmentedReplies() async throws {
        let fake = try FakeAdapter()
        let link = try SerialLink.open(path: fake.path)
        fake.serve { _ in ["7E8 06 41 00", " BE 3F A8 13\r", "\r>"] }
        let reply = try await link.transact("0100", timeout: .seconds(2))
        #expect(reply.text == "7E8 06 41 00 BE 3F A8 13\r\r")
        await link.close()
    }

    @Test func timesOutWithoutPrompt() async throws {
        let fake = try FakeAdapter()
        let link = try SerialLink.open(path: fake.path)
        let start = ContinuousClock.now
        await #expect(throws: OBDError.self) { _ = try await link.transact("0100", timeout: .milliseconds(200)) }
        #expect(ContinuousClock.now - start >= .milliseconds(200))
        #expect(fake.readCommand(timeout: .milliseconds(200)) == "0100")
        await link.close()
    }

    @Test func cancellationStopsWaiting() async throws {
        let fake = try FakeAdapter()
        let link = try SerialLink.open(path: fake.path)
        let task = Task { try await link.transact("0100", timeout: .seconds(10)) }
        try await Task.sleep(for: .milliseconds(100))
        let start = ContinuousClock.now
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Abbruch erwartet")
        } catch let error as OBDError {
            #expect(error == .cancelled)
        }
        #expect(ContinuousClock.now - start < .seconds(1))
        _ = fake
        await link.close()
    }

    @Test func secondOpenIsRejected() async throws {
        let fake = try FakeAdapter()
        let link = try SerialLink.open(path: fake.path)
        #expect(throws: OBDError.portBusy(fake.path)) { _ = try SerialLink.open(path: fake.path) }
        await link.close()
        let reopened = try SerialLink.open(path: fake.path)
        await reopened.close()
    }

    @Test func staleInputIsDiscarded() async throws {
        let fake = try FakeAdapter()
        let link = try SerialLink.open(path: fake.path)
        fake.send("GARBAGE\r>")
        try await Task.sleep(for: .milliseconds(100))
        fake.serve { _ in ["OK\r\r>"] }
        #expect(try await link.transact("ATE0", timeout: .seconds(2)).text == "OK\r\r")
        await link.close()
    }

    @Test func closedLinkRefusesTransactions() async throws {
        let fake = try FakeAdapter()
        let link = try SerialLink.open(path: fake.path)
        await link.close()
        await #expect(throws: OBDError.disconnected) { _ = try await link.transact("ATI", timeout: .seconds(1)) }
        _ = fake
    }

    @Test func missingDeviceFailsToOpen() {
        #expect(throws: OBDError.self) { _ = try SerialLink.open(path: "/dev/cu.does-not-exist-openobd") }
    }
}
