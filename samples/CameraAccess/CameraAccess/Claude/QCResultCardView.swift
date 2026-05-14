import SwiftUI

// MARK: - Score Color Helper

private func scoreColor(_ score: String) -> Color {
  switch score.uppercased() {
  case "GREEN": return Color(red: 0, green: 176.0 / 255.0, blue: 80.0 / 255.0)       // #00B050
  case "AMBER": return Color(red: 1.0, green: 192.0 / 255.0, blue: 0)                 // #FFC000
  case "RED": return Color(red: 1.0, green: 0, blue: 0)                                // #FF0000
  default: return .gray
  }
}

private func statusBadgeColor(_ status: String?) -> Color {
  guard let status else { return .gray }
  switch status.lowercased() {
  case "acceptable": return .green
  case "warning": return .orange
  case "reject": return .red
  default: return .gray
  }
}

private func confidenceBandLabel(_ confidence: Double) -> String {
  switch confidence {
  case 0.86...: return "Confidence: High"
  case 0.66..<0.86: return "Confidence: Medium"
  default: return "Confidence: Low"
  }
}

private func confidenceBandColor(_ confidence: Double) -> Color {
  switch confidence {
  case 0.86...: return .green
  case 0.66..<0.86: return .orange
  default: return .red
  }
}

// MARK: - QC Result Card

struct QCResultCardView: View {
  let result: QCResult
  let onCopy: () -> Void
  let onSpeak: () -> Void
  let onShare: () -> Void
  let onNext: () -> Void

  @State private var showCopied = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {

        // Image type + commodity header
        HStack {
          Text(formatImageType(result.imageType))
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.2))
            .cornerRadius(8)

          if let commodity = result.commodity {
            Text(formatCommodity(commodity))
              .font(.system(size: 15, weight: .semibold))
              .foregroundColor(.white)
          }

          if let variety = result.variety {
            Text("(\(variety))")
              .font(.system(size: 13))
              .foregroundColor(.white.opacity(0.7))
          }

          Spacer()

          // Confidence band (deterministic, avoids suspicious repeated hard values)
          Text(confidenceBandLabel(result.confidence))
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(confidenceBandColor(result.confidence))
        }

        // Overall Score + Action
        HStack(spacing: 12) {
          // Score badge
          Text(result.overallScore)
            .font(.system(size: 18, weight: .black))
            .foregroundColor(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(scoreColor(result.overallScore))
            .cornerRadius(8)

          VStack(alignment: .leading, spacing: 2) {
            Text(formatAction(result.recommendedAction))
              .font(.system(size: 14, weight: .semibold))
              .foregroundColor(scoreColor(result.overallScore))
            if result.repackRequired {
              Text("Repack required")
                .font(.system(size: 12))
                .foregroundColor(.orange)
            }
          }

          Spacer()
        }

        // Compliance flags (critical — shown prominently)
        if !result.complianceFlags.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(result.complianceFlags, id: \.self) { flag in
              HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                  .font(.system(size: 11))
                  .foregroundColor(.red)
                Text(formatFlag(flag))
                  .font(.system(size: 12, weight: .medium))
                  .foregroundColor(.red)
              }
            }
          }
          .padding(8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.red.opacity(0.15))
          .cornerRadius(8)
        }

        // Summary
        Text(result.summary)
          .font(.system(size: 13))
          .foregroundColor(.white.opacity(0.9))

        // Origin + Supplier
        if result.originDetected != nil || result.supplierDetected != nil {
          HStack(spacing: 16) {
            if let origin = result.originDetected {
              Label(origin, systemImage: "globe")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
            }
            if let supplier = result.supplierDetected {
              Label(supplier, systemImage: "building.2")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
            }
          }
        }

        // Packaging assessment
        if let pkg = result.packaging {
          PackagingRow(packaging: pkg)
        }

        // Quality assessment
        if let quality = result.quality {
          QualityRow(quality: quality)
        }

        // Measurements
        if let m = result.measurementsDetected,
           m.temperatureF != nil || m.temperatureC != nil || m.brix != nil || m.weightLbs != nil {
          MeasurementsRow(measurements: m)
        }

        // Defects
        if !result.defects.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            Text("Defects (\(result.defects.count))")
              .font(.system(size: 12, weight: .semibold))
              .foregroundColor(.white.opacity(0.7))

            ForEach(Array(result.defects.enumerated()), id: \.offset) { _, defect in
              DefectRow(defect: defect)
            }
          }
        }

        // SOP Coverage
        if let sop = result.sopCoverage {
          SOPCoverageRow(sop: sop)
        }

        // Action buttons
        HStack(spacing: 8) {
          Button(action: {
            onCopy()
            showCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
              showCopied = false
            }
          }) {
            Label(showCopied ? "Copied" : "Copy JSON", systemImage: showCopied ? "checkmark" : "doc.on.clipboard")
              .font(.system(size: 12, weight: .medium))
              .foregroundColor(.white)
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .background(Color.white.opacity(0.15))
              .cornerRadius(16)
          }

          Button(action: onSpeak) {
            Label("Read Aloud", systemImage: "speaker.wave.2")
              .font(.system(size: 12, weight: .medium))
              .foregroundColor(.white)
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .background(Color.white.opacity(0.15))
              .cornerRadius(16)
          }

          Button(action: onShare) {
            Label("Share", systemImage: "square.and.arrow.up")
              .font(.system(size: 12, weight: .medium))
              .foregroundColor(.white)
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .background(Color.white.opacity(0.15))
              .cornerRadius(16)
          }

          Spacer()

          Button(action: onNext) {
            Label("Next Photo", systemImage: "camera")
              .font(.system(size: 12, weight: .medium))
              .foregroundColor(.black)
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .background(Color.white)
              .cornerRadius(16)
          }
        }
      }
      .padding(16)
    }
    .background(Color.black.opacity(0.75))
    .cornerRadius(16)
  }

  // MARK: - Formatters

  private func formatImageType(_ type: String) -> String {
    type.replacingOccurrences(of: "_", with: " ").uppercased()
  }

  private func formatCommodity(_ commodity: String) -> String {
    commodity.replacingOccurrences(of: "_", with: " ").capitalized
  }

  private func formatAction(_ action: String) -> String {
    action.replacingOccurrences(of: "_", with: " ").capitalized
  }

  private func formatFlag(_ flag: String) -> String {
    flag.replacingOccurrences(of: "_", with: " ").capitalized
  }
}

// MARK: - Sub-components

private struct PackagingRow: View {
  let packaging: PackagingAssessment

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Packaging")
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.white.opacity(0.7))

      HStack(spacing: 8) {
        if let outer = packaging.outer {
          StatusPill(label: "Outer", status: outer)
        }
        if let inner = packaging.inner {
          StatusPill(label: "Inner", status: inner)
        }
        if let primary = packaging.primary {
          StatusPill(label: "Primary", status: primary)
        }
        if let packing = packaging.packingSecure {
          StatusPill(label: "Packing", status: packing)
        }
      }

      if let pluIssue = packaging.pluIssue, pluIssue != "correct" {
        HStack(spacing: 4) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 10))
            .foregroundColor(.red)
          Text("PLU: \(pluIssue.replacingOccurrences(of: "_", with: " "))")
            .font(.system(size: 11))
            .foregroundColor(.red)
        }
      }
    }
  }
}

private struct QualityRow: View {
  let quality: QualityAssessment

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Quality")
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.white.opacity(0.7))

      HStack(spacing: 8) {
        if let colour = quality.colour {
          StatusPill(label: "Colour", status: colour)
        }
        if let eating = quality.eatingQuality {
          StatusPill(label: "Eating", status: eating)
        }
        if let size = quality.size {
          StatusPill(label: "Size", status: size)
        }
        if let shape = quality.shape {
          StatusPill(label: "Shape", status: shape)
        }
      }
      if let firmness = quality.firmnessVisual {
        Text("Firmness: \(firmness)")
          .font(.system(size: 11))
          .foregroundColor(.white.opacity(0.6))
      }
    }
  }
}

private struct MeasurementsRow: View {
  let measurements: MeasurementsDetected

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Measurements")
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.white.opacity(0.7))

      HStack(spacing: 16) {
        if let tempC = measurements.temperatureC {
          Label(String(format: "%.1f C", tempC), systemImage: "thermometer")
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(.white.opacity(0.8))
        } else if let tempF = measurements.temperatureF {
          Label(String(format: "%.1f F", tempF), systemImage: "thermometer")
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(.white.opacity(0.8))
        }
        if let brix = measurements.brix {
          Label(String(format: "%.1f Bx", brix), systemImage: "drop")
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(.white.opacity(0.8))
        }
        if let weight = measurements.weightLbs {
          Label(String(format: "%.1f lbs", weight), systemImage: "scalemass")
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(.white.opacity(0.8))
        }
      }
    }
  }
}

private struct DefectRow: View {
  let defect: QCDefect

  var body: some View {
    HStack(spacing: 6) {
      Text(defect.severity.uppercased())
        .font(.system(size: 9, weight: .bold))
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(defect.severity == "critical" ? Color.red :
                      defect.severity == "major" ? Color.orange : Color.yellow.opacity(0.7))
        .cornerRadius(4)

      Text(defect.type.replacingOccurrences(of: "_", with: " "))
        .font(.system(size: 12))
        .foregroundColor(.white)

      if let pct = defect.estimatedPercentage {
        Text("\(Int(pct))%")
          .font(.system(size: 11, design: .monospaced))
          .foregroundColor(.white.opacity(0.6))
      }

      Text(defect.location.replacingOccurrences(of: "_", with: " "))
        .font(.system(size: 11))
        .foregroundColor(.white.opacity(0.5))

      Spacer()
    }
  }
}

private struct SOPCoverageRow: View {
  let sop: SOPCoverage

  private let allSteps = [
    "load_overview", "label", "fruit_topdown", "defect_closeup",
    "cut_fruit", "temperature_reading", "brix_reading", "weight_check"
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("SOP Coverage")
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.white.opacity(0.7))

      // Show captured vs needed
      let capturedSet = Set(sop.captured)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 4) {
        ForEach(allSteps, id: \.self) { step in
          HStack(spacing: 3) {
            Image(systemName: capturedSet.contains(step) ? "checkmark.square.fill" : "square")
              .font(.system(size: 10))
              .foregroundColor(capturedSet.contains(step) ? .green : .white.opacity(0.4))
            Text(step.replacingOccurrences(of: "_", with: " "))
              .font(.system(size: 10))
              .foregroundColor(capturedSet.contains(step) ? .white : .white.opacity(0.4))
          }
        }
      }
    }
  }
}

private struct StatusPill: View {
  let label: String
  let status: String

  var body: some View {
    VStack(spacing: 1) {
      Text(label)
        .font(.system(size: 9))
        .foregroundColor(.white.opacity(0.5))
      Text(status.capitalized)
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(statusBadgeColor(status))
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 4)
    .background(Color.white.opacity(0.08))
    .cornerRadius(6)
  }
}
