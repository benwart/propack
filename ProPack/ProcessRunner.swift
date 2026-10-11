import Foundation

/// Runs system binaries (`/usr/sbin/lsof`, `/usr/bin/ditto`) without blocking the caller.
enum ProcessRunner {
    struct Output: Sendable {
        let status: Int32
        let stdout: Data
        let stderr: Data

        var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
        var stderrString: String {
            String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private final class DataBox: @unchecked Sendable {
        var data = Data()
    }

    static func run(_ executable: String, arguments: [String]) async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardInput = FileHandle.nullDevice

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                // Drain stderr on a second thread so neither pipe can fill up and stall the child.
                let errBox = DataBox()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()

                continuation.resume(returning: Output(
                    status: process.terminationStatus,
                    stdout: outData,
                    stderr: errBox.data
                ))
            }
        }
    }
}
