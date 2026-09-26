import SwiftUI

struct ResultView: View {
  let scan: ScanRecord
  @ObservedObject var controller: ScanController
  private var color: Color {
    scan.verdict?.isBuy == true
      ? FVColor.lime : (scan.verdict == nil ? FVColor.amber : FVColor.tomato)
  }
  var body: some View {
    ZStack {
      FVColor.ink.ignoresSafeArea()
      VStack(alignment: .leading) {
        HStack {
          Label(
            scan.source.label, systemImage: scan.source == .metaGlasses ? "eyeglasses" : "iphone")
          Spacer()
          Button("Scan again") { controller.newScan() }
        }.font(.subheadline.bold()).foregroundStyle(FVColor.cream.opacity(0.75))
        Spacer()
        if let verdict = scan.verdict {
          Text(scan.fruit?.displayName.uppercased() ?? "FRUIT").font(.caption.bold()).tracking(2.2)
            .foregroundStyle(color)
          Text(verdict.rawValue).font(.largeTitle.weight(.black)).fontDesign(.rounded)
            .foregroundStyle(FVColor.cream).padding(.top, 10)
          Text(scan.reason ?? "Look for even color and firm, unbroken skin.").font(
            .title2.weight(.medium)
          ).foregroundStyle(FVColor.cream.opacity(0.86)).padding(.top, 20)
            .accessibilityLabel(
              "Reason: \(scan.reason ?? "Look for even color and firm, unbroken skin.")")
        } else {
          Text("TRY AGAIN").font(.caption.bold()).tracking(2.2).foregroundStyle(FVColor.amber)
          Text(controller.shopperMessage ?? "I couldn’t judge that fruit.").font(.largeTitle.bold())
            .fontDesign(.rounded).foregroundStyle(FVColor.cream).padding(.top, 10)
          if scan.state == .needsRetry {
            Button("Try this photo again") { Task { await controller.retry(scan) } }.buttonStyle(
              FVPrimaryButtonStyle(color: FVColor.amber)
            ).padding(.top, 24)
          }
        }
        Spacer()
        if scan.verdict != nil && controller.showsFeedback {
          FeedbackPrompt(
            good: { controller.vote(.good) }, bad: { controller.vote(.notGood) },
            dismiss: controller.dismissFeedback)
        }
        Button("Scan another fruit") { controller.newScan() }.buttonStyle(
          FVPrimaryButtonStyle(color: color)
        ).padding(.top, 16)
      }.padding(26)
    }
  }
}

struct FeedbackPrompt: View {
  let good, bad, dismiss: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading) {
          Text("WHEN YOU EAT IT").font(.caption2.bold()).tracking(1.2)
          Text("Was it good?").font(.title2.bold())
        }
        Spacer()
        Button(action: dismiss) { Image(systemName: "xmark").frame(width: 38, height: 38) }
      }
      HStack {
        Button(action: good) {
          Label("Yes", systemImage: "hand.thumbsup.fill").frame(maxWidth: .infinity)
        }
        Button(action: bad) {
          Label("No", systemImage: "hand.thumbsdown.fill").frame(maxWidth: .infinity)
        }
      }.font(.headline)
    }.foregroundStyle(FVColor.ink).padding(20).background(
      FVColor.cream, in: RoundedRectangle(cornerRadius: 24))
  }
}

struct FVPrimaryButtonStyle: ButtonStyle {
  let color: Color
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.headline.bold()).foregroundStyle(FVColor.ink).frame(
      maxWidth: .infinity
    ).padding(.vertical, 18).background(
      color.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 18))
  }
}
