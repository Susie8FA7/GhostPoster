import Foundation

struct GhostSiteResponse: Decodable {
    let site: GhostSite
}

struct GhostSite: Decodable, Sendable {
    let title: String
    let description: String?
    let url: String
    let version: String?
}

struct GhostPostsResponse: Decodable {
    let posts: [GhostPost]
}

struct GhostPost: Decodable, Sendable {
    let id: String
    let title: String
    let status: String
    let url: String?
}

struct GhostImagesResponse: Decodable {
    let images: [GhostImage]
}

struct GhostImage: Decodable, Sendable {
    let url: String
    let ref: String?
}

struct CreateGhostPostsRequest: Encodable {
    let posts: [CreateGhostPost]
}

struct CreateGhostPost: Encodable {
    let title: String
    let html: String
    let status: String
    let featureImage: String?

    enum CodingKeys: String, CodingKey {
        case title
        case html
        case status
        case featureImage = "feature_image"
    }
}

struct GhostAPIErrorResponse: Decodable {
    let errors: [GhostAPIErrorDetail]
}

struct GhostAPIErrorDetail: Decodable {
    let message: String
    let type: String?
    let context: String?
}
