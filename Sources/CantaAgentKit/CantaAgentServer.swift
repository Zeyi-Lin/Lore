import Foundation

/// Immutable configuration for the local, loopback-only Agent API.
public struct AgentServerConfig: Sendable {
    /// Loopback port to bind. Pass \`0\` to let the system choose an ephemeral
    /// port (useful for tests); the actual port is reported through
    /// \`AgentServerStatus.running(port:)\`.
    public var port: UInt16
    /// Directory that contains \`library.json\`, \`Images/\`, and \`Thumbnails/\`.
    public var libraryRoot: URL

    public init(port: UInt16 = 4242, libraryRoot: URL) {
        self.port = port
        self.libraryRoot = libraryRoot
    }
}

/// Lifecycle state of the embedded Agent API.
public enum AgentServerStatus: Equatable, Sendable {
    case stopped
    case starting
    case running(port: UInt16)
    case failed(String)

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

/// Local HTTP server that exposes the Canta library to coding agents.
///
/// The server binds exclusively to the IPv4 loopback address (127.0.0.1), so
/// it is reachable only by processes on the same Mac. The library file is read
/// fresh for every request. This type is the source-compatible contract used
/// by the Canta app; the implementation lives in CantaAgentKit.
public final class CantaAgentServer {
    public let config: AgentServerConfig

    /// Called on a background queue whenever lifecycle state changes.
    public var onStatusChange: (@Sendable (AgentServerStatus) -> Void)?

    /// Called once on a background queue after a successful POST /api/v1/pins
    /// atomically appended a pin to library.json. The app can use this to
    /// reload its in-memory library without polling the file.
    public var onLibraryChanged: (@Sendable () -> Void)?

    private let stateLock = NSLock()
    private var storedStatus: AgentServerStatus = .stopped
    private var storedBoundPort: UInt16?
    private var generation: UInt64 = 0
    private var activeServer: HTTPServer?

    private let lifecycleQueue = DispatchQueue(label: "com.canta.agent-server.lifecycle")
    private let callbackQueue = DispatchQueue(label: "com.canta.agent-server.status")

    public init(config: AgentServerConfig) {
        self.config = config
    }

    /// Convenience initializer matching the app's usual call site.
    public convenience init(port: UInt16 = CantaAgentAPI.defaultPort, libraryRoot: URL) {
        self.init(config: AgentServerConfig(port: port, libraryRoot: libraryRoot))
    }

    /// Current lifecycle state. Safe to read from any thread.
    public var status: AgentServerStatus {
        stateLock.lock()
        defer { stateLock.unlock() }
        return storedStatus
    }

    /// The actual bound port while running, otherwise \`nil\`.
    public var runningPort: UInt16? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return storedBoundPort
    }

    /// Convenience URL for the running server, e.g. \`http://127.0.0.1:4242\`.
    public var baseURL: URL? {
        guard let port = runningPort else { return nil }
        return URL(string: "http://127.0.0.1:\(port)")
    }

    /// True when the server is accepting requests.
    public var isRunning: Bool {
        status.isRunning
    }

    /// Starts the server and returns immediately. Starting is asynchronous;
    /// observe \`status\` or \`onStatusChange\` for the bound port.
    public func start() {
        stateLock.lock()
        switch storedStatus {
        case .starting, .running:
            stateLock.unlock()
            return
        default:
            break
        }
        storedStatus = .starting
        storedBoundPort = nil
        generation &+= 1
        let startGeneration = generation
        stateLock.unlock()

        emit(.starting)
        lifecycleQueue.async { [weak self] in
            self?.prepareStart(generation: startGeneration)
        }
    }

    /// Stops the server and releases the listening socket. Safe to call
    /// multiple times; teardown happens asynchronously on an internal queue.
    public func stop() {
        stateLock.lock()
        guard storedStatus != .stopped else {
            stateLock.unlock()
            return
        }
        storedStatus = .stopped
        storedBoundPort = nil
        generation &+= 1
        stateLock.unlock()

        emit(.stopped)
        lifecycleQueue.async { [weak self] in
            self?.takeActiveServer()?.stop()
        }
    }

    deinit {
        stateLock.lock()
        let server = activeServer
        activeServer = nil
        stateLock.unlock()
        server?.stop()
    }

    // MARK: - Lifecycle internals

    private func prepareStart(generation startGeneration: UInt64) {
        takeActiveServer()?.stop()

        let store = LibraryStore(root: config.libraryRoot)
        let ingestor = LibraryIngestor(root: config.libraryRoot)
        ingestor.onLibraryChanged = { [weak self] in
            self?.emitLibraryChanged()
        }
        let router = AgentRouter(
            store: store,
            ingestor: ingestor,
            portProvider: { [weak self] in
                self?.runningPort ?? self?.config.port ?? 0
            }
        )
        let server: HTTPServer
        do {
            server = try HTTPServer(port: config.port)
        } catch {
            failStart("The Agent API could not create a loopback listener: \(error.localizedDescription)", generation: startGeneration)
            return
        }

        server.handler = { request in
            router.handle(request)
        }
        server.bodyLimitProvider = { head in
            router.maxBodyBytes(for: head)
        }
        server.onReady = { [weak self, weak server] port in
            guard let self, let server else { return }
            self.handleReady(port: port, generation: startGeneration, server: server)
        }
        server.onFailure = { [weak self, weak server] message in
            guard let self, let server else { return }
            self.handleFailure(message: message, generation: startGeneration, server: server)
        }

        stateLock.lock()
        guard generation == startGeneration, case .starting = storedStatus else {
            stateLock.unlock()
            server.stop()
            return
        }
        activeServer = server
        stateLock.unlock()
        server.start()
    }

    private func handleReady(port: UInt16, generation readyGeneration: UInt64, server: HTTPServer) {
        stateLock.lock()
        guard generation == readyGeneration, case .starting = storedStatus else {
            stateLock.unlock()
            server.stop()
            return
        }
        storedStatus = .running(port: port)
        storedBoundPort = port
        stateLock.unlock()
        emit(.running(port: port))
    }

    private func handleFailure(message: String, generation failedGeneration: UInt64, server: HTTPServer) {
        stateLock.lock()
        guard generation == failedGeneration else {
            stateLock.unlock()
            server.stop()
            return
        }
        storedStatus = .failed(message)
        storedBoundPort = nil
        if activeServer === server {
            activeServer = nil
        }
        stateLock.unlock()

        emit(.failed(message))
        server.stop()
    }

    private func failStart(_ message: String, generation failedGeneration: UInt64) {
        stateLock.lock()
        guard generation == failedGeneration else {
            stateLock.unlock()
            return
        }
        storedStatus = .failed(message)
        storedBoundPort = nil
        stateLock.unlock()
        emit(.failed(message))
    }

    private func takeActiveServer() -> HTTPServer? {
        stateLock.lock()
        defer { stateLock.unlock() }
        let server = activeServer
        activeServer = nil
        return server
    }

    private func emit(_ status: AgentServerStatus) {
        guard let callback = onStatusChange else { return }
        callbackQueue.async {
            callback(status)
        }
    }

    private func emitLibraryChanged() {
        guard let callback = onLibraryChanged else { return }
        callbackQueue.async {
            callback()
        }
    }
}
