import SwiftUI

struct GlassesSheet: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var glasses: MetaGlassesSource
  @ObservedObject var controller: ScanController
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      Capsule().fill(FVColor.ink.opacity(0.16)).frame(width: 40, height: 5).frame(
        maxWidth: .infinity)
      Image(systemName: "eyeglasses").font(.system(size: 38, weight: .bold)).foregroundStyle(
        FVColor.leaf)
      Text("Scan through Meta glasses").font(.system(size: 32, weight: .black, design: .rounded))
        .foregroundStyle(FVColor.ink)
      Text(
        "The same verdict and training record, whether the photo comes from your phone or glasses."
      ).font(.title3).foregroundStyle(FVColor.ink.opacity(0.7))
      if let message = glasses.message {
        Text(message).foregroundStyle(FVColor.tomato).font(.headline)
      }
      Spacer()
      Button(
        glasses.isRegistered
          ? (glasses.isStreaming ? "Use Meta glasses" : "Start glasses camera")
          : "Connect Meta glasses"
      ) {
        Task {
          if !glasses.isRegistered {
            await glasses.register()
          } else if !glasses.isStreaming {
            let connected = await glasses.connectAndPreview()
            if connected {
              controller.selectedSource = .metaGlasses
              dismiss()
            }
            return
          }
          if glasses.isStreaming {
            controller.selectedSource = .metaGlasses
            dismiss()
          }
        }
      }.buttonStyle(FVPrimaryButtonStyle(color: FVColor.lime))
      Button("Use iPhone camera") {
        glasses.stop()
        controller.selectedSource = .iPhone
        dismiss()
      }.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
    }.padding(24).background(FVColor.cream)
  }
}
