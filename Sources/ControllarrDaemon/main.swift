import Foundation
import Dispatch
import Darwin
import ControllarrCore
import Persistence

struct CLIOptions {
    var webUIRoot: URL?
    var storeDirectory: URL?
    var hostOverride: String?
    var portOverride: Int?
    var showHelp: Bool = false
}

enum CLIError: Error, LocalizedError {
    case missingValue(String)
    case invalidValue(flag: String, value: String)
    case unknownArgument(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)."
        case .invalidValue(let flag, let value):
            return "Invalid value for \(flag): \(value)"
        case .unknownArgument(let argument):
            return "Unknown argument: \(argument)"
        }
    }
}

final class SignalTrap {
    private let stream: AsyncStream<Int32>
    private var continuation: AsyncStream<Int32>.Continuation?
    private var sources: [DispatchSourceSignal] = []

    init(signals: [Int32] = [SIGINT, SIGTERM]) {
        var captured: AsyncStream<Int32>.Continuation?
        self.stream = AsyncStream { continuation in
            captured = continuation
        }
        self.continuation = captured

        for signalNumber in signals {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in
                self?.continuation?.yield(signalNumber)
                self?.continuation?.finish()
            }
            source.resume()
            sources.append(source)
        }
    }

    func wait() async -> Int32? {
        for await signal in stream {
            return signal
        }
        return nil
    }
}

@main
struct ControllarrDaemonMain {
    static func main() async {
        do {
            let options = try parse(Array(CommandLine.arguments.dropFirst()))
            if options.showHelp {
                printUsage()
                return
            }

            let webUIRoot = options.webUIRoot ?? inferWebUIRoot()
            let runtime = await ControllarrRuntime(
                webUIRoot: webUIRoot,
                storeDirectory: options.storeDirectory,
                httpHostOverride: options.hostOverride,
                httpPortOverride: options.portOverride
            )

            try await runtime.start()

            let settings = await runtime.store.settings()
            let host = options.hostOverride ?? settings.webUIHost
            let port = options.portOverride ?? settings.webUIPort
            let stateDir = options.storeDirectory ?? PersistenceStore.defaultDirectory()

            print("[ControllarrDaemon] running at http://\(host):\(port)")
            print("[ControllarrDaemon] state directory: \(stateDir.path)")
            if let webUIRoot {
                print("[ControllarrDaemon] serving WebUI from: \(webUIRoot.path)")
            } else {
                print("[ControllarrDaemon] WebUI root not found; API-only mode is active")
            }
            print("[ControllarrDaemon] press Ctrl-C to stop")

            let signals = SignalTrap()
            let received = await signals.wait() ?? 0
            print("[ControllarrDaemon] received signal \(received), shutting down")
            await runtime.shutdown()
        } catch {
            FileHandle.standardError.write(
                Data("[ControllarrDaemon] \(error.localizedDescription)\n".utf8)
            )
            printUsage()
            Darwin.exit(1)
        }
    }

    private static func parse(_ args: [String]) throws -> CLIOptions {
        var options = CLIOptions()
        var index = 0

        while index < args.count {
            let argument = args[index]
            switch argument {
            case "--help", "-h":
                options.showHelp = true
                index += 1

            case "--webui-root":
                index += 1
                guard index < args.count else { throw CLIError.missingValue(argument) }
                options.webUIRoot = resolveURL(args[index])
                index += 1

            case "--state-dir":
                index += 1
                guard index < args.count else { throw CLIError.missingValue(argument) }
                options.storeDirectory = resolveURL(args[index])
                index += 1

            case "--host":
                index += 1
                guard index < args.count else { throw CLIError.missingValue(argument) }
                options.hostOverride = args[index]
                index += 1

            case "--port":
                index += 1
                guard index < args.count else { throw CLIError.missingValue(argument) }
                guard let port = Int(args[index]), (1...65_535).contains(port) else {
                    throw CLIError.invalidValue(flag: argument, value: args[index])
                }
                options.portOverride = port
                index += 1

            default:
                throw CLIError.unknownArgument(argument)
            }
        }

        return options
    }

    private static func resolveURL(_ path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(path)
            .standardizedFileURL
    }

    private static func inferWebUIRoot() -> URL? {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            cwd.appendingPathComponent("WebUI/dist", isDirectory: true),
            cwd.appendingPathComponent("dist", isDirectory: true),
        ]

        for candidate in candidates {
            let index = candidate.appendingPathComponent("index.html")
            if FileManager.default.fileExists(atPath: index.path) {
                return candidate
            }
        }

        return nil
    }

    private static func printUsage() {
        let usage = """
        Usage: swift run ControllarrDaemon [options]

          --webui-root <path>   Serve the built WebUI from this directory
          --state-dir <path>    Override the Controllarr state directory
          --host <host>         Override the configured HTTP bind host
          --port <port>         Override the configured HTTP bind port
          --help, -h            Show this help text
        """
        print(usage)
    }
}
