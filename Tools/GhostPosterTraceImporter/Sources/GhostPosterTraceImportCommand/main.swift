import Darwin
import Foundation
import GhostPosterTraceImportCore

private let usage = """
Usage:
  ghostposter-trace-import configure
  ghostposter-trace-import config show
  ghostposter-trace-import config clear
  ghostposter-trace-import <trace.json>
  ghostposter-trace-import <trace.json> --dry-run
  ghostposter-trace-import <trace.json> --send
"""

private func writeError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

private func prompt(_ label: String, defaultValue: String? = nil) -> String {
    if let defaultValue {
        print("\(label) [\(defaultValue)]: ", terminator: "")
    } else {
        print("\(label): ", terminator: "")
    }
    fflush(stdout)
    let value = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? (defaultValue ?? "") : value
}

private func promptSecret(_ label: String) -> String {
    print("\(label): ", terminator: "")
    fflush(stdout)
    var original = termios()
    guard tcgetattr(STDIN_FILENO, &original) == 0 else {
        return readLine() ?? ""
    }
    var hidden = original
    hidden.c_lflag &= ~tcflag_t(ECHO)
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &hidden)
    defer {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        print("")
    }
    return readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

private func configure(_ store: LangfuseConfigurationStore) throws {
    let current = try? store.status()
    let defaultURL = current?.baseURL?.absoluteString
        ?? LangfuseConfigurationStore.defaultBaseURL.absoluteString
    let baseURLValue = prompt("Langfuse Base URL", defaultValue: defaultURL)
    guard let baseURL = URL(string: baseURLValue),
          LangfuseConfigurationStore.isValidBaseURL(baseURL) else {
        throw LangfuseConfigurationError.invalidBaseURL
    }
    let publicKey = prompt("Langfuse Public Key")
    guard !publicKey.isEmpty else {
        throw LangfuseConfigurationError.missingPublicKey
    }
    let secretKey = promptSecret("Langfuse Secret Key")
    guard !secretKey.isEmpty else {
        throw LangfuseConfigurationError.missingSecretKey
    }
    try store.save(
        baseURL: baseURL,
        publicKey: publicKey,
        secretKey: secretKey
    )
    print("Langfuse設定を保存しました。API KeyはmacOS Keychainに保存されています。")
}

private func showConfiguration(_ store: LangfuseConfigurationStore) throws {
    let status = try store.status()
    print("Base URL: \(status.baseURL?.absoluteString ?? "未設定")")
    print("Public Key: \(status.hasPublicKey ? "設定済み" : "未設定")")
    print("Secret Key: \(status.hasSecretKey ? "設定済み" : "未設定")")
    if ProcessInfo.processInfo.environment["LANGFUSE_BASE_URL"] != nil
        || ProcessInfo.processInfo.environment["LANGFUSE_PUBLIC_KEY"] != nil
        || ProcessInfo.processInfo.environment["LANGFUSE_SECRET_KEY"] != nil {
        print("Environment overrides: あり")
    }
}

private func importTrace(path: String, mode: String?) async throws {
    let document = try TraceImporter.load(from: URL(fileURLWithPath: path))
    print(TraceImporter.summarize(document).description)
    guard let mode else { return }

    let payload = OpenTelemetryMapper.map(document)
    switch mode {
    case "--dry-run":
        let data = try OpenTelemetryMapper.encodedJSON(
            payload,
            prettyPrinted: true
        )
        print(String(data: data, encoding: .utf8) ?? "")
    case "--send":
        let configuration = try LangfuseConfigurationStore().resolve()
        try await LangfuseOpenTelemetryClient().send(
            payload: payload,
            configuration: configuration
        )
        print("Langfuseへ送信しました。")
    default:
        throw CommandError.invalidArguments
    }
}

private enum CommandError: LocalizedError {
    case invalidArguments

    var errorDescription: String? { usage }
}

private func run() async throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let store = LangfuseConfigurationStore()

    if arguments == ["configure"] {
        try configure(store)
    } else if arguments == ["config", "show"] {
        try showConfiguration(store)
    } else if arguments == ["config", "clear"] {
        try store.clear()
        print("Langfuse設定を削除しました。")
    } else if arguments.count == 1 {
        try await importTrace(path: arguments[0], mode: nil)
    } else if arguments.count == 2,
              ["--dry-run", "--send"].contains(arguments[1]) {
        try await importTrace(path: arguments[0], mode: arguments[1])
    } else {
        throw CommandError.invalidArguments
    }
}

do {
    try await run()
} catch {
    let message = (error as? LocalizedError)?.errorDescription
        ?? error.localizedDescription
    writeError("Error: \(message)")
    exit(error is CommandError ? 64 : 1)
}
