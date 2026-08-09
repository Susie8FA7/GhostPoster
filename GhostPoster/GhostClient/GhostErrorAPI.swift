import Foundation

enum GhostError: LocalizedError {
    case invalidURL
    case invalidAdminAPIKey
    case jwtGenerationFailed
    case invalidResponse
    case api(statusCode: Int, message: String)
    case decodingFailed(Error)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Ghost URL が正しくありません。"
        case .invalidAdminAPIKey:
            return "Admin API Key は ID:SECRET の形式で入力してください。"
        case .jwtGenerationFailed:
            return "認証トークンを生成できませんでした。"
        case .invalidResponse:
            return "Ghostから不正な応答を受信しました。"
        case .api(let statusCode, let message):
            return "Ghost API エラー（\(statusCode)）: \(message)"
        case .decodingFailed:
            return "Ghostの応答を読み取れませんでした。"
        case .network(let error):
            return "通信に失敗しました: \(error.localizedDescription)"
        }
    }
}
