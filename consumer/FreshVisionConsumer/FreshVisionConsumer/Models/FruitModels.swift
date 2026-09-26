import Foundation

enum FruitKind: String, Codable, CaseIterable, Sendable {
  case banana, grapes, strawberries, avocado, apple
  var displayName: String { rawValue.capitalized }
}

enum FruitVerdict: String, Codable, CaseIterable, Sendable {
  case readyNow = "Buy — ready now"
  case ripeSoon = "Buy — ripe in 2–3 days"
  case overripe = "Skip — overripe"
  case underripe = "Skip — underripe"
  case damaged = "Skip — damaged"
  var isBuy: Bool { self == .readyNow || self == .ripeSoon }
}

enum AnalysisIssue: String, Codable, Sendable {
  case noFruit = "no_fruit"
  case multipleFruits = "multiple_fruits"
  case poorLighting = "poor_lighting"
  case unsupportedFruit = "unsupported_fruit"
}

enum CaptureSource: String, Codable, Sendable {
  case iPhone = "iphone"
  case metaGlasses = "meta_glasses"
  var label: String { self == .iPhone ? "iPhone" : "Meta glasses" }
}

enum FeedbackChoice: String, Codable, Sendable {
  case good
  case notGood = "not_good"
}
enum ScanState: String, Codable, Sendable {
  case captured, analyzing, complete
  case needsRetry = "needs_retry"
}

struct CapturedFruitImage: Sendable {
  let jpegData: Data
  let source: CaptureSource
  let capturedAt: Date
}

struct FruitAnalysisResponse: Codable, Equatable, Sendable {
  let supported: Bool
  let fruit: FruitKind?
  let verdict: FruitVerdict?
  let reason: String
  let issue: AnalysisIssue?
  let confidence: Double

  var shopperMessage: String? {
    switch issue {
    case .noFruit: "I can’t see one piece of fruit. Try moving closer."
    case .multipleFruits: "Show me one piece of fruit at a time."
    case .poorLighting: "It’s too dark to judge. Move into better light."
    case .unsupportedFruit: "I only know 5 fruits so far."
    case nil: nil
    }
  }
}
