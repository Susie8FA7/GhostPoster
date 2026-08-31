import Foundation

public enum LangfuseClientError: LocalizedError, Equatable {
    case invalidEndpoint
    case invalidResponse
    case rejected(statusCode: Int, response: String)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "Langfuse OpenTelemetry endpointを生成できません。"
        case .invalidResponse:
            "LangfuseからHTTPレスポンスを取得できませんでした。"
        case .rejected(let statusCode, let response):
            "Langfuseへの送信に失敗しました (HTTP \(statusCode)): \(response)"
        }
    }
}

public struct LangfuseOpenTelemetryClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func makeRequest(
        payload: OTLPExportRequest,
        configuration: LangfuseConfiguration
    ) throws -> URLRequest {
        guard let endpoint = Self.traceEndpoint(baseURL: configuration.baseURL) else {
            throw LangfuseClientError.invalidEndpoint
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = try OpenTelemetryMapper.encodedJSON(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("4", forHTTPHeaderField: "x-langfuse-ingestion-version")
        let credentials = Data(
            "\(configuration.publicKey):\(configuration.secretKey)".utf8
        ).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        return request
    }

    public func send(
        payload: OTLPExportRequest,
        configuration: LangfuseConfiguration
    ) async throws {
        let request = try makeRequest(
            payload: payload,
            configuration: configuration
        )
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LangfuseClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let responseText = String(data: data, encoding: .utf8) ?? ""
            throw LangfuseClientError.rejected(
                statusCode: httpResponse.statusCode,
                response: String(responseText.prefix(500))
            )
        }
    }

    public static func traceEndpoint(baseURL: URL) -> URL? {
        let trimmed = baseURL.absoluteString.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
        if trimmed.hasSuffix("/api/public/otel/v1/traces") {
            return URL(string: trimmed)
        }
        if trimmed.hasSuffix("/api/public/otel") {
            return URL(string: trimmed + "/v1/traces")
        }
        return URL(string: trimmed + "/api/public/otel/v1/traces")
    }
}
