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
    supabaseURL?.host != nil && !supabaseAnonKey.isEmpty && !supabaseAnonKey.contains("public-anon")
  }
  func functionURL(_ name: String) -> URL? { supabaseURL?.appending(path: "functions/v1/\(name)") }
}
