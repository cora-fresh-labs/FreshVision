import Foundation
import Security

private struct AuthCredentials: Codable, Sendable {
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
  private let store = CredentialStore()
  private var credentials: AuthCredentials?

  init(configuration: AppConfiguration, session: URLSession) {
    self.configuration = configuration
    self.session = session
    credentials = store.load()
  }

  func accessToken() async throws -> String {
    if let credentials, credentials.expiresAt.timeIntervalSinceNow > 300 {
      return credentials.accessToken
    }
    if let credentials {
      do { return try await refresh(credentials.refreshToken).accessToken } catch {
        store.clear()
        self.credentials = nil
      }
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

private struct CredentialStore: Sendable {
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
