import Foundation
import Security

struct AuthCredentials: Codable, Sendable {
  let accessToken: String
  let refreshToken: String
  let expiresAt: Date
}

private struct AuthResponse: Decodable {
  let accessToken: String
  let refreshToken: String
  let expiresIn: Double

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case expiresIn = "expires_in"
  }
}

actor AuthSession {
  private let configuration: AppConfiguration
  private let session: URLSession
  private let store: any AuthCredentialStorage
  private var credentials: AuthCredentials?
  private var pendingToken: Task<String, Error>?

  init(configuration: AppConfiguration, session: URLSession, store: (any AuthCredentialStorage)? = nil) {
    self.configuration = configuration
    self.session = session
    let credentialStore = store ?? CredentialStore()
    self.store = credentialStore
    credentials = credentialStore.load()
  }

  func accessToken() async throws -> String {
    if let pendingToken { return try await pendingToken.value }
    let task = Task { try await self.currentToken() }
    pendingToken = task
    defer { pendingToken = nil }
    return try await task.value
  }

  private func currentToken() async throws -> String {
    if let credentials, credentials.expiresAt.timeIntervalSinceNow > 300 {
      return credentials.accessToken
    }
    if let credentials {
      // Preserve ownership on a network or server failure. A new anonymous
      // identity could no longer sync or delete this installation's scans.
      return try await refresh(credentials.refreshToken).accessToken
    }
    return try await signInAnonymously().accessToken
  }

  private func signInAnonymously() async throws -> AuthCredentials {
    guard let url = configuration.authURL("signup") else { throw FreshVisionAPIError.notConfigured }
    return try await request(url: url, body: Data("{}".utf8))
  }

  private func refresh(_ token: String) async throws -> AuthCredentials {
    guard let base = configuration.authURL("token") else {
      throw FreshVisionAPIError.notConfigured
    }
    let url = base.appending(queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")])
    let body = try JSONEncoder().encode(["refresh_token": token])
    return try await request(url: url, body: body)
  }

  private func request(url: URL, body: Data) async throws -> AuthCredentials {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(configuration.supabaseAnonKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(configuration.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw FreshVisionAPIError.serverMessage("FreshVision could not establish a private session.")
    }
    let value = try JSONDecoder().decode(AuthResponse.self, from: data)
    let credentials = AuthCredentials(
      accessToken: value.accessToken,
      refreshToken: value.refreshToken,
      expiresAt: Date().addingTimeInterval(value.expiresIn)
    )
    try store.save(credentials)
    self.credentials = credentials
    return credentials
  }
}

protocol AuthCredentialStorage: Sendable {
  func load() -> AuthCredentials?
  func save(_ credentials: AuthCredentials) throws
}

private struct CredentialStore: AuthCredentialStorage {
  private let service = "com.coraglobalprojects.freshvision.consumer.auth"
  private let account = "anonymous-session"

  func load() -> AuthCredentials? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var value: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
      let data = value as? Data
    else { return nil }
    return try? JSONDecoder().decode(AuthCredentials.self, from: data)
  }

  func save(_ credentials: AuthCredentials) throws {
    let data = try JSONEncoder().encode(credentials)
    let key: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let status = SecItemUpdate(
      key as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    if status == errSecItemNotFound {
      var insert = key
      insert[kSecValueData as String] = data
      insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
        throw FreshVisionAPIError.invalidResponse
      }
    } else if status != errSecSuccess {
      throw FreshVisionAPIError.invalidResponse
    }
  }

  func clear() { SecItemDelete([
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: account,
  ] as CFDictionary) }
}
