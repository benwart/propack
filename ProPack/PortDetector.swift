import AppKit

/// Locates the ProPresenter network API port.
///
/// 1. Find running ProPresenter processes by bundle identifier (`NSWorkspace`, no subprocess needed).
/// 2. List their listening TCP sockets with
///    `/usr/sbin/lsof -nP -a -p <PID> -iTCP -sTCP:LISTEN`.
/// 3. Probe each port's `GET /version` concurrently and return the first that answers like ProPresenter.
struct PortDetector: Sendable {
    /// Matches `com.renewedvision.propresenter` and variants such as `…propresenter7`.
    static let bundleIdentifierPrefix = "com.renewedvision.propresenter"
    static let ephemeralRange = 49152...65535

    struct Detection: Sendable {
        let port: Int
        let pid: pid_t
        let version: PPVersion
    }

    enum DetectionError: LocalizedError {
        case notRunning
        case lsofFailed(String)
        case noListeningPorts
        case apiNotResponding(ports: [Int])
        case notProPresenter(port: Int)

        var errorDescription: String? {
            switch self {
            case .notRunning:
                "ProPresenter doesn't appear to be running. Launch it and try again."
            case .lsofFailed(let message):
                "Couldn't inspect ProPresenter's network ports (lsof: \(message))."
            case .noListeningPorts:
                "ProPresenter is running but isn't listening on any TCP port. Enable Network in ProPresenter ▸ Settings ▸ Network."
            case .apiNotResponding(let ports):
                "ProPresenter is listening on \(ports.map(String.init).joined(separator: ", ")), but none answered the API. Make sure Network is enabled, or enter the port manually."
            case .notProPresenter(let port):
                "Port \(port) answered, but it doesn't look like the ProPresenter API."
            }
        }
    }

    var probeTimeout: TimeInterval = 1.5

    // MARK: Public

    func detect() async throws -> Detection {
        let pids = await Self.runningProPresenterPIDs()
        guard !pids.isEmpty else { throw DetectionError.notRunning }

        var allPorts: [Int] = []
        for pid in pids {
            let ports = try await listeningPorts(pid: pid)
            allPorts += ports
            if let (port, version) = await probe(ports: ports) {
                return Detection(port: port, pid: pid, version: version)
            }
        }
        throw allPorts.isEmpty ? DetectionError.noListeningPorts : DetectionError.apiNotResponding(ports: allPorts)
    }

    /// Verifies a specific (e.g. user-entered) port.
    func verify(port: Int) async throws -> PPVersion {
        let version = try await ProPresenterClient(port: port, timeout: 4).version()
        guard version.looksLikeProPresenter else { throw DetectionError.notProPresenter(port: port) }
        return version
    }

    // MARK: Steps

    @MainActor
    static func runningProPresenterPIDs() -> [pid_t] {
        NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier?.lowercased().hasPrefix(bundleIdentifierPrefix) ?? false }
            .map(\.processIdentifier)
    }

    func listeningPorts(pid: pid_t) async throws -> [Int] {
        let output = try await ProcessRunner.run(
            "/usr/sbin/lsof",
            // -Fn: machine-readable output; one "n<addr>:<port>" line per socket.
            arguments: ["-nP", "-a", "-p", String(pid), "-iTCP", "-sTCP:LISTEN", "-Fn"]
        )
        // lsof exits 1 with no output when nothing matches; that's "no ports", not a failure.
        if output.stdout.isEmpty {
            if output.status == 0 || output.status == 1 { return [] }
            throw DetectionError.lsofFailed(output.stderrString.isEmpty ? "exit \(output.status)" : output.stderrString)
        }
        return Self.parseLsofPorts(output.stdoutString)
    }

    /// Parses `lsof -Fn` output. Ports in the ephemeral range are returned first.
    static func parseLsofPorts(_ output: String) -> [Int] {
        var seen = Set<Int>()
        var ports: [Int] = []
        for line in output.split(whereSeparator: \.isNewline) where line.hasPrefix("n") {
            guard let colon = line.lastIndex(of: ":"),
                  let port = Int(line[line.index(after: colon)...]),
                  seen.insert(port).inserted else { continue }
            ports.append(port)
        }
        return ports.sorted { a, b in
            let aEphemeral = ephemeralRange.contains(a)
            let bEphemeral = ephemeralRange.contains(b)
            return aEphemeral != bEphemeral ? aEphemeral : a < b
        }
    }

    /// Probes all ports concurrently; returns the first that responds like ProPresenter.
    func probe(ports: [Int]) async -> (Int, PPVersion)? {
        let timeout = probeTimeout
        return await withTaskGroup(of: (Int, PPVersion)?.self) { group in
            for port in ports {
                group.addTask {
                    let client = ProPresenterClient(port: port, timeout: timeout)
                    guard let version = try? await client.version(), version.looksLikeProPresenter else {
                        return nil
                    }
                    return (port, version)
                }
            }
            for await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }
}
