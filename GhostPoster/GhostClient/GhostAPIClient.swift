import Foundation

struct GhostClient: Sendable {
    private let baseURL: URL
    private let adminAPIKey: String
    private let cloudflareAccessClientID: String
    private let cloudflareAccessClientSecret: String
    private let session: URLSession

    init(
        baseURL: URL,
        adminAPIKey: String,
        cloudflareAccessClientID: String,
        cloudflareAccessClientSecret: String,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.adminAPIKey = adminAPIKey
        self.cloudflareAccessClientID = cloudflareAccessClientID
        self.cloudflareAccessClientSecret = cloudflareAccessClientSecret
        self.session = session
    }

    func fetchSite() async throws -> GhostSite {
        let response: GhostSiteResponse = try await request(
            path: "ghost/api/admin/site/",
            method: "GET"
        )
        return response.site
    }

    func createDraft(
        title: String,
        html: String,
        featureImageURL: String? = nil
    ) async throws -> GhostPost {
        let payload = CreateGhostPostsRequest(
            posts: [
                CreateGhostPost(
                    title: title,
                    html: html,
                    status: "draft",
                    featureImage: featureImageURL
                )
            ]
        )
        let response: GhostPostsResponse = try await request(
            path: "ghost/api/admin/posts/?source=html",
            method: "POST",
            body: try JSONEncoder().encode(payload)
        )
        guard let post = response.posts.first else {
            throw GhostError.invalidResponse
        }
        return post
    }

    func uploadFeatureImage(
        jpegData: Data,
        filename: String = "feature-image.jpg"
    ) async throws -> GhostImage {
        let token = try GhostJWT.makeToken(adminAPIKey: adminAPIKey)
        guard let url = URL(
            string: "ghost/api/admin/images/upload/",
            relativeTo: normalizedBaseURL
        ) else {
            throw GhostError.invalidURL
        }

        let boundary = "GhostPoster-\(UUID().uuidString)"
        var body = Data()
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
        )
        body.appendUTF8("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpegData)
        body.appendUTF8("\r\n--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"purpose\"\r\n\r\n")
        body.appendUTF8("image\r\n")
        body.appendUTF8("--\(boundary)--\r\n")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 60
        request.setValue("Ghost \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(cloudflareAccessClientID, forHTTPHeaderField: "CF-Access-Client-Id")
        request.setValue(cloudflareAccessClientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("v5.0", forHTTPHeaderField: "Accept-Version")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GhostError.network(error)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GhostError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(GhostAPIErrorResponse.self, from: data)
            let message = apiError?.errors.first?.message
                ?? String(data: data, encoding: .utf8)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw GhostError.api(statusCode: httpResponse.statusCode, message: message)
        }
        do {
            let response = try JSONDecoder().decode(GhostImagesResponse.self, from: data)
            guard let image = response.images.first else {
                throw GhostError.invalidResponse
            }
            return image
        } catch let error as GhostError {
            throw error
        } catch {
            throw GhostError.decodingFailed(error)
        }
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        body: Data? = nil
    ) async throws -> Response {
        let token = try GhostJWT.makeToken(adminAPIKey: adminAPIKey)
        guard let url = URL(string: path, relativeTo: normalizedBaseURL) else {
            throw GhostError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("Ghost \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(cloudflareAccessClientID, forHTTPHeaderField: "CF-Access-Client-Id")
        request.setValue(cloudflareAccessClientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("v5.0", forHTTPHeaderField: "Accept-Version")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GhostError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GhostError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(GhostAPIErrorResponse.self, from: data)
            let message = apiError?.errors.first?.message
                ?? String(data: data, encoding: .utf8)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw GhostError.api(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "不明"
            let preview = String((String(data: data, encoding: .utf8) ?? "").prefix(500))
            throw GhostError.api(
                statusCode: httpResponse.statusCode,
                message: "JSONの解析に失敗しました。Content-Type: \(contentType) Response: \(preview)"
            )
        }
    }

    private var normalizedBaseURL: URL {
        baseURL.absoluteString.hasSuffix("/")
            ? baseURL
            : URL(string: baseURL.absoluteString + "/")!
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}
