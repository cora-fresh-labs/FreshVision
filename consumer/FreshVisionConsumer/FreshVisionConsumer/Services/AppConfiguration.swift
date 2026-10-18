import Foundation

struct AppConfiguration: Sendable {
  let supabaseURL: URL?
  let supabaseAnonKey: String
  static let live = AppConfiguration(
    supabaseURL: (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String).flatMap(
      URL.init),
    supabaseAnonKey: Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
  )
  var isConfigured: Bool {
    guard supabaseURL?.scheme == "https", supabaseURL?.host != nil,
      !supabaseAnonKey.isEmpty, !supabaseAnonKey.contains("public-anon"),
      !supabaseAnonKey.hasPrefix("sb_secret_")
    else { return false }
    let parts = supabaseAnonKey.split(separator: ".")
    if parts.count == 3 {
      var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
      payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
      if let data = Data(base64Encoded: payload),
         let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         claims["role"] as? String == "service_role" { return false }
    }
    return true
  }
  func functionURL(_ name: String) -> URL? { supabaseURL?.appending(path: "functions/v1/\(name)") }
  func authURL(_ path: String) -> URL? { supabaseURL?.appending(path: "auth/v1/\(path)") }
}
