import SwiftData
import SwiftUI

struct HistoryView: View {
  @Environment(\.dismiss) private var dismiss
  @Query(sort: \ScanRecord.capturedAt, order: .reverse) private var scans: [ScanRecord]
  @ObservedObject var controller: ScanController
  private var visibleScans: [ScanRecord] { scans.filter { !$0.pendingDeletion } }
  var body: some View {
    NavigationStack {
      Group {
        if visibleScans.isEmpty {
          ContentUnavailableView(
            "No scans yet", systemImage: "camera.viewfinder",
            description: Text("Your fruit scans will appear here."))
        } else {
          List(visibleScans) { scan in
            HistoryRow(scan: scan, controller: controller).listRowSeparator(.hidden)
              .onTapGesture { controller.show(scan); dismiss() }
              .listRowBackground(Color.clear)
              .swipeActions {
                Button("Delete", role: .destructive) { Task { await controller.delete(scan) } }
              }
          }.listStyle(.plain)
        }
      }.safeAreaInset(edge: .bottom) {
        Text("Photos stay on this phone and upload to private FreshVision storage when connected. Photos go to Anthropic for analysis. Spoken verdict text goes to ElevenLabs. Swipe a scan to delete the FreshVision copies.")
          .font(.caption).foregroundStyle(FVColor.ink.opacity(0.66)).padding(12)
          .frame(maxWidth: .infinity).background(FVColor.cream)
      }.background(FVColor.cream.ignoresSafeArea()).navigationTitle("History").toolbar {
        Button("Done") { dismiss() }
      }
    }
  }
}

private struct HistoryRow: View {
  let scan: ScanRecord
  @ObservedObject var controller: ScanController
  var body: some View {
    HStack(spacing: 14) {
      Group {
        if let image = controller.image(for: scan) {
          Image(uiImage: image).resizable().scaledToFill()
        } else {
          FVColor.ink.opacity(0.08)
        }
      }.frame(width: 76, height: 88).clipShape(RoundedRectangle(cornerRadius: 16))
      VStack(alignment: .leading, spacing: 7) {
        Text(scan.fruit?.displayName ?? "Fruit scan").font(.caption.bold()).textCase(.uppercase)
        Text(scan.verdict?.rawValue ?? "Needs another look").font(.headline).foregroundStyle(
          FVColor.ink)
        Text(scan.capturedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
          .foregroundStyle(FVColor.ink.opacity(0.55))
        if let feedback = scan.feedback {
          Label(
            feedback == .good ? "Good" : "Not good",
            systemImage: feedback == .good ? "hand.thumbsup.fill" : "hand.thumbsdown.fill"
          ).font(.caption.bold())
        } else if scan.verdict != nil {
          HStack {
            Button {
              controller.vote(.good, for: scan)
            } label: {
              Image(systemName: "hand.thumbsup").frame(width: 44, height: 44)
            }.accessibilityLabel("It was good")
            Button {
              controller.vote(.notGood, for: scan)
            } label: {
              Image(systemName: "hand.thumbsdown").frame(width: 44, height: 44)
            }.accessibilityLabel("It was not good")
          }
        }
      }
    }.padding(12).background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 22))
  }
}
