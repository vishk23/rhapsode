import Foundation

enum LLMAPITransport {
    private static func makeEphemeralSession(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        // URLSession's resource timeout is session-scoped, while each caller
        // already puts its configured timeout on the URLRequest. Keep both
        // session timers aligned with that request instead of applying one
        // global timeout to every provider and operation.
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        return URLSession(configuration: configuration)
    }

    /// The long-lived upload session serves requests with differing per-request
    /// timeouts, so its session-level timers are ceilings, not per-call values:
    /// the resource ceiling must exceed every caller's timeout or it silently
    /// caps them and kills long transfers (upstream freeflow issue #253).
    private static func makeUploadSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 600
        return URLSession(configuration: configuration)
    }

    private static func timeout(for request: URLRequest) -> TimeInterval {
        let requestTimeout = request.timeoutInterval
        guard requestTimeout.isFinite, requestTimeout > 0 else {
            return 60
        }
        return requestTimeout
    }

    static func data(
        for request: URLRequest
    ) async throws -> (Data, URLResponse) {
        let session = makeEphemeralSession(timeout: timeout(for: request))
        defer { session.finishTasksAndInvalidate() }
        return try await session.data(for: request)
    }

    // MARK: - Upload session (reused, self-healing)

    private static let uploadSessionLock = NSLock()
    private static var _uploadSession: URLSession?

    private static func uploadSession() -> URLSession {
        uploadSessionLock.lock()
        defer { uploadSessionLock.unlock() }
        if let session = _uploadSession { return session }
        let session = makeUploadSession()
        _uploadSession = session
        return session
    }

    private static func discardUploadSession() {
        uploadSessionLock.lock()
        defer { uploadSessionLock.unlock() }
        _uploadSession?.finishTasksAndInvalidate()
        _uploadSession = nil
    }

    static func upload(
        for request: URLRequest,
        from bodyData: Data
    ) async throws -> (Data, URLResponse) {
        // Reuse a keep-alive session so each dictation skips DNS + TLS setup, but
        // discard it on any error so a bad connection cannot poison later uploads
        // (the original fresh-session-per-upload guarantee, kept self-healing).
        do {
            return try await uploadSession().upload(for: request, from: bodyData)
        } catch {
            discardUploadSession()
            throw error
        }
    }

    /// Opens the TCP+TLS connection to the transcription host while the user is
    /// still speaking, so the upload on key-release starts on a warm connection.
    /// Any response (401/405 included) means the handshake completed; errors are
    /// ignored — this is purely opportunistic.
    static func prewarm(baseURL urlString: String) {
        guard let url = URL(string: urlString)?.appendingPathComponent("models") else { return }
        Task.detached(priority: .utility) {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 5
            _ = try? await uploadSession().data(for: request)
        }
    }
}
