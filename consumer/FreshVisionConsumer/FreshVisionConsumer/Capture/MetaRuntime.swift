import Foundation
import MWDATCore

@MainActor
enum MetaRuntime {
  private(set) static var interface: WearablesInterface?
  private(set) static var setupMessage: String?

  static func configure() {
    let configuration = Bundle.main.object(forInfoDictionaryKey: "MWDAT") as? [String: Any]
    let appID = configuration?["MetaAppID"] as? String ?? ""
    let clientToken = configuration?["ClientToken"] as? String ?? ""
    guard !appID.isEmpty, !clientToken.isEmpty else {
      setupMessage = "Meta glasses setup is waiting for Developer Center credentials."
      return
    }
    do {
      try Wearables.configure()
      interface = Wearables.shared
    } catch {
      setupMessage = "Meta glasses setup could not start."
    }
  }
}
