import AppKit

/// Locates the ProPresenter network API port.
///
/// Multi-strategy detection:
/// 1. Direct lsof command inspection: `lsof -nP -a -c ProPresenter -c 'ProPresenter Helper' -iTCP -sTCP:LISTEN -Fn`.
///    This directly captures helper processes (such as "ProPresenter Helper (Network)") where ProPresenter delegates its HTTP server.
/// 2. Process inspection via pgrep & NSWorkspace PIDs: finds both parent and child processes and queries their listening sockets.
/// 3. Ephemeral port probe: queries candidate ports concurrently against `GET /version`.
struct PortDetector: Sendable {
    static let bundleIdentifierPrefix = "com.renewedvision.propresenter"
    static let ephemeralRange = 49152...65535

    struct Detection: Sendable {
        let port: Int
        let pid: pid_t?
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
        // Strategy 1: Fast direct lsof inspection matching ProPresenter process names (including helper processes).
        var candidatePorts = (try? await listeningPortsByCommand()) ?? []

        // Strategy 2: Collect all candidate PIDs from NSWorkspace and pgrep.
        let pids = await Self.allProPresenterPIDs()
        if candidatePorts.isEmpty {
            for pid in pids {
                if let ports = try? await listeningPorts(pid: pid) {
                    candidatePorts.append(contentsOf: ports)
                }
            }
        }

        // Deduplicate ports preserving ephemeral prioritization
        let uniquePorts = Self.sortAndDeduplicatePorts(candidatePorts)

        if !uniquePorts.isEmpty {
            if let (port, version) = await probe(ports: uniquePorts) {
                return Detection(port: port, pid: pids.first, version: version)
            }
            throw DetectionError.apiNotResponding(ports: uniquePorts)
        }

        // If no ports were found, verify if ProPresenter is at least running
        guard !pids.isEmpty else {
            throw DetectionError.notRunning
        }

        throw DetectionError.noListeningPorts
    }

    /// Verifies a specific (e.g. user-entered) port.
    func verify(port: Int) async throws -> PPVersion {
        let version = try await ProPresenterClient(port: port, timeout: 4).version()
        guard version.looksLikeProPresenter else { throw DetectionError.notProPresenter(port: port) }
        return version
    }

    // MARK: Process & Socket Discovery

    /// Inspects listening sockets by executable/command name prefix.
    /// This reliably catches helper daemons like "ProPresenter Helper (Network)".
    func listeningPortsByCommand() async throws -> [Int] {
        let output = try await ProcessRunner.run(
            "/usr/sbin/lsof",
            arguments: [
                "-nP", "-a",
                "-c", "ProPresenter",
                "-c", "ProPresenter Helper",
                "-iTCP", "-sTCP:LISTEN",
                "-Fn"
            ]
        )
        return Self.parseLsofPorts(output.stdoutString)
    }

    /// Discovers PIDs using both NSWorkspace (GUI apps) and pgrep (all matching sub-processes and helpers).
    @MainActor
    static func allProPresenterPIDs() -> [pid_t] {
        var pids = Set<pid_t>()

        // 1. NSWorkspace running applications
        for app in NSWorkspace.shared.runningApplications {
            if let bundleId = app.bundleIdentifier?.lowercased(),
               bundleId.hasPrefix(bundleIdentifierPrefix) {
                pids.insert(app.processIdentifier)
            } else if app.localizedName?.localizedCaseInsensitiveContains("ProPresenter") ?? false {
                pids.insert(app.processIdentifier)
            }
        }

        // 2. pgrep for ProPresenter processes and helpers
        if let pgrepOutput = try? ProcessRunner.runSync(
            "/usr/bin/pgrep",
            arguments: ["-i", "propresenter"]
        ) {
            for line in pgrepOutput.split(whereSeparator: \.isNewline) {
                if let pid = pid_t(line.trimmingCharacters(in: .whitespaces)) {
                    pids.insert(pid)
                }
            }
        }

        return Array(pids)
    }

    func listeningPorts(pid: pid_t) async throws -> [Int] {
        let output = try await ProcessRunner.run(
            "/usr/sbin/lsof",
            arguments: ["-nP", "-a", "-p", String(pid), "-iTCP", "-sTCP:LISTEN", "-Fn"]
        )
        if output.stdout.isEmpty {
            if output.status == 0 || output.status == 1 { return [] }
            throw DetectionError.lsofFailed(output.stderrString.isEmpty ? "exit \(output.status)" : output.stderrString)
        }
        return Self.parseLsofPorts(output.stdoutString)
    }

    /// Parses `lsof -Fn` output.
    static func parseLsofPorts(_ output: String) -> [Int] {
        var ports: [Int] = []
        for line in output.split(whereSeparator: \.isNewline) where line.hasPrefix("n") {
            guard let colon = line.lastIndex(of: ":"),
                  let port = Int(line[line.index(after: colon)...]) else { continue }
            ports.append(port)
        }
        return sortAndDeduplicatePorts(ports)
    }

    /// Deduplicates and prioritizes ephemeral port ranges (49152...65535).
    static func sortAndDeduplicatePorts(_ ports: [Int]) -> [Int] {
        var seen = Set<Int>()
        let filtered = ports.filter { seen.insert($0).inserted }
        return filtered.sorted { a, b in
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
