import Foundation
import SwiftData

@Model
final class ScanRecord {
  @Attribute(.unique) var id: UUID
  var capturedAt: Date
  var imageFilename: String
  var sourceRaw: String
  var deviceModel: String
  var stateRaw: String
  var fruitRaw: String?
  var verdictRaw: String?
  var reason: String?
  var issueRaw: String?
  var confidence: Double?
  var feedbackRaw: String?
  var feedbackAt: Date?
  var scanSyncedAt: Date?
  var feedbackSyncedAt: Date?
  var lastSyncError: String?

  init(
    id: UUID = UUID(), capturedAt: Date, imageFilename: String, source: CaptureSource,
    deviceModel: String
  ) {
    self.id = id
    self.capturedAt = capturedAt
    self.imageFilename = imageFilename
    self.sourceRaw = source.rawValue
    self.deviceModel = deviceModel
    self.stateRaw = ScanState.captured.rawValue
  }

  var source: CaptureSource { CaptureSource(rawValue: sourceRaw) ?? .iPhone }
  var state: ScanState {
    get { ScanState(rawValue: stateRaw) ?? .captured }
    set { stateRaw = newValue.rawValue }
  }
  var fruit: FruitKind? {
    get { fruitRaw.flatMap(FruitKind.init) }
    set { fruitRaw = newValue?.rawValue }
  }
  var verdict: FruitVerdict? {
    get { verdictRaw.flatMap(FruitVerdict.init) }
    set { verdictRaw = newValue?.rawValue }
  }
  var issue: AnalysisIssue? {
    get { issueRaw.flatMap(AnalysisIssue.init) }
    set { issueRaw = newValue?.rawValue }
  }
  var feedback: FeedbackChoice? {
    get { feedbackRaw.flatMap(FeedbackChoice.init) }
    set { feedbackRaw = newValue?.rawValue }
  }
}
