import Foundation

enum LLMAPITransport {
    private static let requestSession: URLSession = {
        makeEphemeralSession()
    }()

    private static func makeEphemeralSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        // The resource timeout must exceed every per-request timeoutInterval callers
        // set (transcription uploads configure their own), or it silently caps them
        // and kills any transfer past 30s — long dictations and slow providers
        // (upstream freeflow issue #253).
        configuration.timeoutIntervalForResource = 600
        return URLSession(configuration: configuration)
    }

    static func data(
        for request: URLRequest
    ) async throws -> (Data, URLResponse) {
        try await requestSession.data(for: request)
    }

    // MARK: - Upload session (reused, self-healing)

    private static let uploadSessionLock = NSLock()
    private static var _uploadSession: URLSession?

    private static func uploadSession() -> URLSession {
        uploadSessionLock.lock()
        defer { uploadSessionLock.unlock() }
        if let session = _uploadSession { return session }
        let session = makeEphemeralSession()
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
