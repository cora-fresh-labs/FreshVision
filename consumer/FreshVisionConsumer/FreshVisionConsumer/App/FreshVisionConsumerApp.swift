import MWDATCore
import SwiftData
import SwiftUI

@main
struct FreshVisionConsumerApp: App {
  private let container: ModelContainer?
  private let storeError: String?
  init() {
    MetaRuntime.configure()
    do {
      container = try ModelContainer(
        for: Schema(versionedSchema: FreshVisionSchemaV1.self),
        migrationPlan: FreshVisionMigrationPlan.self
      )
      storeError = nil
    } catch {
      container = nil
      storeError = error.localizedDescription
    }
  }
  var body: some Scene {
    WindowGroup {
      if let container {
        RootView().modelContainer(container)
      } else {
        StoreRecoveryView(detail: storeError)
      }
    }
  }
}

private struct StoreRecoveryView: View {
  let detail: String?
  var body: some View {
    ZStack {
      FVColor.ink.ignoresSafeArea()
      VStack(spacing: 18) {
        Image(systemName: "externaldrive.badge.exclamationmark").font(.system(size: 44))
          .foregroundStyle(FVColor.amber)
        Text("Your scan history needs attention").font(.largeTitle.bold()).multilineTextAlignment(.center)
          .foregroundStyle(FVColor.cream)
        Text("Your saved photos have not been deleted. Close and reopen FreshVision. If this returns, contact the test team before removing the app.")
          .font(.title3).multilineTextAlignment(.center).foregroundStyle(FVColor.cream.opacity(0.82))
        if let detail {
          Text(detail).font(.caption).foregroundStyle(FVColor.cream.opacity(0.55))
            .multilineTextAlignment(.center)
        }
      }.padding(28)
    }
  }
}
