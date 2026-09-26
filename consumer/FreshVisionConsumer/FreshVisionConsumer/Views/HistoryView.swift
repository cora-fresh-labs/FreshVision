import SwiftData
import SwiftUI

struct HistoryView: View {
  @Environment(\.dismiss) private var dismiss
  @Query(sort: \ScanRecord.capturedAt, order: .reverse) private var scans: [ScanRecord]
  @ObservedObject var controller: ScanController
  var body: some View {
    NavigationStack {
      Group {
        if scans.isEmpty {
          ContentUnavailableView(
            "No scans yet", systemImage: "camera.viewfinder",
            description: Text("Your fruit scans will appear here."))
        } else {
          List(scans) { scan in
            HistoryRow(scan: scan, controller: controller).listRowSeparator(.hidden)
              .listRowBackground(Color.clear)
          }.listStyle(.plain)
        }
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
      AsyncImage(url: controller.imageURL(for: scan)) {
        $0.resizable().scaledToFill()
      } placeholder: {
        FVColor.ink.opacity(0.08)
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
