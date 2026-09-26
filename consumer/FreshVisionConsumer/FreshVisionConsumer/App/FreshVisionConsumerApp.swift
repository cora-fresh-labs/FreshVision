import MWDATCore
import SwiftData
import SwiftUI

@main
struct FreshVisionConsumerApp: App {
  private let container: ModelContainer
  init() {
    MetaRuntime.configure()
    do { container = try ModelContainer(for: ScanRecord.self) } catch {
      fatalError("FreshVision history could not be created: \(error.localizedDescription)")
    }
  }
  var body: some Scene { WindowGroup { RootView() }.modelContainer(container) }
}
