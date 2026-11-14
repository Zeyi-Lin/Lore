import Foundation
import Network

// MARK: - Listener

/// A minimal HTTP/1.1 server built on Network.framework. The listener is
/// permanently bound to the IPv4 loopback address only, so the API is never
/// reachable from other machines or interfaces.
final class HTTPServer {
    typealias Handler = (HTTPRequest) -> HTTPResponse

    /// Invoked exactly once when the listener is ready, with the actual bound port.
    var onReady: ((UInt16) -> Void)?
    /// Invoked when the listener fails to start (e.g. address already in use).
    var onFailure: ((String) -> Void)?
    /// Invoked for every fully parsed request.
    var handler: Handler?
    /// Returns how many body bytes a route wants buffered before dispatch.
    /// Return 0 for routes that answer from the head alone (GET/HEAD/etc).
    var bodyLimitProvider: ((HTTPRequestHead) -> Int)?

    private let queue = DispatchQueue(label: "com.canta.agent-server.listener")
    private let queueKey = DispatchSpecificKey<Void>()
    private let connectionQueue = DispatchQueue(label: "com.canta.agent-server.connections", attributes: .concurrent)
    private let stateLock = NSLock()
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: HTTPConnection] = [:]
    private var stopped = false
    private let maxConnections = 64

    init(port: UInt16) throws {
        queue.setSpecific(key: queueKey, value: ())
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let requestedPort: NWEndpoint.Port = port == 0 ? .any : (NWEndpoint.Port(rawValue: port) ?? .any)
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: requestedPort)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        self.listener = listener
    }

    func start() {
        queue.async { [weak self] in
            guard let self, let listener = self.listener else { return }
            listener.stateUpdateHandler = { [weak self] state in
                self?.handleListenerState(state)
            }
            listener.start(queue: self.queue)
        }
    }

    func stop() {
        // Calling stop() from the listener queue (for example from a failed
        // listener state handler) must not dispatch_sync onto itself; that
        // would trap in libdispatch. Teardown is idempotent, so run it inline
        // when we are already on the listener queue.
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            stopOnQueue()
        } else {
            queue.sync {
                stopOnQueue()
            }
        }
    }

    private func stopOnQueue() {
        guard !stopped else { return }
        stopped = true
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        stateLock.lock()
        let active = Array(connections.values)
        connections.removeAll()
        stateLock.unlock()
        for connection in active {
            connection.cancel()
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener?.port?.rawValue, port != 0 else {
                onFailure?("The Agent API listener became ready without a bound port.")
                return
            }
            onReady?(port)
        case .failed(let error):
            onFailure?("Could not listen on 127.0.0.1: \(error.localizedDescription)")
        case .cancelled:
            break
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        stateLock.lock()
        guard !stopped else {
            stateLock.unlock()
            connection.cancel()
            return
        }
        if connections.count >= maxConnections {
            stateLock.unlock()
            connection.cancel()
            return
        }
        stateLock.unlock()

        let httpConnection = HTTPConnection(
            connection: connection,
            queue: connectionQueue,
            handler: handler,
            bodyLimitProvider: bodyLimitProvider
        )
        let identifier = ObjectIdentifier(httpConnection)
        stateLock.lock()
        connections[identifier] = httpConnection
        stateLock.unlock()
        httpConnection.onClose = { [weak self, weak httpConnection] in
            guard let self else { return }
            self.stateLock.lock()
            if let httpConnection {
                self.connections.removeValue(forKey: ObjectIdentifier(httpConnection))
            }
            self.stateLock.unlock()
        }
        httpConnection.start()
    }
}

// MARK: - Connection

/// Handles a single HTTP/1.1 request/response exchange. One request per
/// connection; every response advertises "Connection: close".
final class HTTPConnection {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let handler: HTTPServer.Handler?
    private let bodyLimitProvider: ((HTTPRequestHead) -> Int)?
    private let requestTimeout: TimeInterval = 20

    private var buffer = Data()
    private var parsedHead: HTTPRequestHead?
    private var bodyStartOffset = 0
    private var finished = false
    private var timeoutWorkItem: DispatchWorkItem?
    var onClose: (() -> Void)?

    init(
        connection: NWConnection,
        queue: DispatchQueue,
        handler: HTTPServer.Handler?,
        bodyLimitProvider: ((HTTPRequestHead) -> Int)?
    ) {
        self.connection = connection
        self.queue = queue
        self.handler = handler
        self.bodyLimitProvider = bodyLimitProvider
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.beginExchange()
            case .failed, .cancelled:
                self.close()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func cancel() {
        close()
    }

    private func beginExchange() {
        scheduleTimeout()
        receive()
    }

    private func scheduleTimeout() {
        let item = DispatchWorkItem { [weak self] in
            self?.close()
        }
        timeoutWorkItem = item
        queue.asyncAfter(deadline: .now() + requestTimeout, execute: item)
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, !self.finished else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
            }
            self.advance(receiveComplete: isComplete, receiveError: error)
        }
    }

    /// Drives the head/body state machine over the bytes received so far.
    private func advance(receiveComplete: Bool, receiveError: Error?) {
        if let head = parsedHead {
            finishOrWaitForBody(head, receiveComplete: receiveComplete, receiveError: receiveError)
            return
        }
        switch HTTPRequestParser.parseHead(buffer) {
        case .incomplete:
            if receiveComplete || receiveError != nil {
                if buffer.isEmpty {
                    close()
                } else {
                    fail(APIError(status: 400, code: "bad_request", message: "The connection was closed before a complete HTTP request head was received."))
                }
            } else {
                receive()
            }
        case .failure(let error):
            fail(error)
        case .head(let head, let bodyStart):
            parsedHead = head
            bodyStartOffset = bodyStart
            let limit = bodyLimitProvider?(head) ?? 0
            if limit <= 0 {
                // This route answers from the head alone; any body is ignored.
                complete(head, body: Data())
            } else if head.contentLength > limit {
                fail(APIError(status: 413, code: "request_body_too_large", message: "Request bodies on this endpoint are limited to \(limit) bytes."))
            } else {
                finishOrWaitForBody(head, receiveComplete: receiveComplete, receiveError: receiveError)
            }
        }
    }

    private func finishOrWaitForBody(_ head: HTTPRequestHead, receiveComplete: Bool, receiveError: Error?) {
        let available = buffer.count - bodyStartOffset
        if available >= head.contentLength {
            let start = buffer.index(buffer.startIndex, offsetBy: bodyStartOffset)
            let end = buffer.index(start, offsetBy: head.contentLength)
            complete(head, body: Data(buffer[start..<end]))
        } else if receiveComplete || receiveError != nil {
            fail(APIError(status: 400, code: "bad_request", message: "The connection was closed before the complete request body was received."))
        } else {
            receive()
        }
    }

    private func complete(_ head: HTTPRequestHead, body: Data) {
        guard !finished else { return }
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        let request = HTTPRequest(head: head, body: body)
        let response = handler?(request) ?? HTTPResponse.error(status: 500, code: "server_unavailable", message: "No request handler is installed.")
        send(response, includeBody: !request.isHead)
    }

    private func fail(_ error: APIError) {
        guard !finished else { return }
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        send(HTTPResponse.error(status: error.status, code: error.code, message: error.message), includeBody: true)
    }

    private func send(_ response: HTTPResponse, includeBody: Bool) {
        guard !finished else { return }
        let data = response.serialized(includingBody: includeBody)
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            self?.close()
        })
    }

    private func close() {
        guard !finished else { return }
        finished = true
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        onClose?()
        onClose = nil
    }
}
