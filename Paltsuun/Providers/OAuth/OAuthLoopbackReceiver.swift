import Foundation
import Network

enum OAuthLoopbackError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        switch self {
        case .timedOut: "Sign-in timed out. Try again."
        }
    }
}

/// Receives an OAuth authorization response sent to `http://127.0.0.1:<port>`, the redirect
/// recommended for native apps by RFC 8252. Accepts a single redirect.
final class OAuthLoopbackReceiver {
    private let listener: NWListener
    private var ready: CheckedContinuation<URL, Error>?
    private var waiting: CheckedContinuation<URL, Error>?
    private var result: Result<URL, Error>?
    private var timeoutTask: Task<Void, Never>?

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    /// Starts listening and returns the redirect URI to send to the authorization server.
    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            ready = continuation
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated { self?.listenerStateChanged(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            listener.start(queue: .main)
        }
    }

    /// Waits for the browser to be redirected back and returns the redirect URL with its query.
    func waitForRedirect(timeout: Duration) async throws -> URL {
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled { self?.finish(.failure(OAuthLoopbackError.timedOut)) }
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if let result {
                    continuation.resume(with: result)
                } else {
                    waiting = continuation
                }
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }

    func stop() {
        listener.cancel()
        ready?.resume(throwing: CancellationError())
        ready = nil
        finish(.failure(CancellationError()))
    }

    private func listenerStateChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener.port else { return }
            ready?.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)")!)
            ready = nil
        case .failed(let error):
            ready?.resume(throwing: error)
            ready = nil
            finish(.failure(error))
        default:
            break
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard self.result == nil else { return }
        self.result = result
        timeoutTask?.cancel()
        waiting?.resume(with: result)
        waiting = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            MainActor.assumeIsolated { self?.handleRequest(data, on: connection) }
        }
    }

    private func handleRequest(_ data: Data?, on connection: NWConnection) {
        // The request line looks like "GET /?code=…&state=… HTTP/1.1".
        let requestLine = data.flatMap { String(data: $0, encoding: .utf8) }?
            .components(separatedBy: "\r\n").first ?? ""
        let parts = requestLine.split(separator: " ")
        guard result == nil, parts.count >= 2, parts[0] == "GET",
              let url = URL(string: "http://127.0.0.1\(parts[1])"),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.contains(where: { $0.name == "code" || $0.name == "error" })
        else {
            // E.g. the browser asking for /favicon.ico.
            respond(on: connection, status: "404 Not Found", message: "Not found.")
            return
        }
        respond(on: connection, status: "200 OK", message: "You can close this tab and return to Paltsuun.")
        finish(.success(url))
    }

    private func respond(on connection: NWConnection, status: String, message: String) {
        let body = Data("""
            <!doctype html><html><head><meta charset="utf-8"><title>Paltsuun</title></head>
            <body style="font: 16px -apple-system, sans-serif; text-align: center; margin-top: 20vh">
            <p>\(message)</p></body></html>
            """.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}
