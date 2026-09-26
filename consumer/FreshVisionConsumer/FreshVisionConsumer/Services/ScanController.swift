import SwiftData
import UIKit

@MainActor
final class ScanController: ObservableObject {
  enum Phase: Equatable { case camera, capturing, analyzing, result }
  @Published private(set) var phase: Phase = .camera
  @Published private(set) var activeScan: ScanRecord?
  @Published var shopperMessage: String?
  @Published var showsFeedback = true
  @Published var selectedSource: CaptureSource = .iPhone
  private let api = FreshVisionAPI()
  private let images = try! ImageStore()
  private let speaker = VerdictSpeaker()
  private var context: ModelContext?

  func attach(_ context: ModelContext) {
    self.context = context
    Task { await syncPending() }
  }
  func syncPending() async {
    guard let context,
      let scans = try? context.fetch(
        FetchDescriptor<ScanRecord>(sortBy: [SortDescriptor(\.capturedAt)]))
    else { return }
    for scan in scans where scan.scanSyncedAt == nil {
      if scan.state != .complete, let data = try? images.data(for: scan.imageFilename) {
        await analyze(scan, data, presentResult: false)
      }
      await syncScan(scan)
    }
    for scan in scans where scan.feedback != nil && scan.feedbackSyncedAt == nil {
      await syncFeedback(scan)
    }
  }
  func scan(using phone: IPhoneCameraSource, glasses: MetaGlassesSource) async {
    guard phase == .camera else { return }
    phase = .capturing
    shopperMessage = nil
    do {
      let capture: CapturedFruitImage
      if selectedSource == .iPhone {
        capture = try await phone.capture()
      } else {
        capture = try await glasses.capture()
      }
      try await process(capture)
    } catch {
      phase = .camera
      shopperMessage = error.localizedDescription
    }
  }
  func newScan() {
    activeScan = nil
    shopperMessage = nil
    showsFeedback = true
    phase = .camera
  }
  func dismissFeedback() { showsFeedback = false }
  func imageURL(for scan: ScanRecord) -> URL { images.url(for: scan.imageFilename) }
  func vote(_ choice: FeedbackChoice, for value: ScanRecord? = nil) {
    guard let scan = value ?? activeScan else { return }
    scan.feedback = choice
    scan.feedbackAt = Date()
    scan.feedbackSyncedAt = nil
    try? context?.save()
    showsFeedback = false
    Task { await syncFeedback(scan) }
  }
  func retry(_ scan: ScanRecord) async {
    guard let data = try? images.data(for: scan.imageFilename) else { return }
    activeScan = scan
    phase = .analyzing
    await analyze(scan, data)
    await syncScan(scan)
  }

  private func process(_ capture: CapturedFruitImage) async throws {
    guard let context else { throw FreshVisionAPIError.invalidResponse }
    guard let data = UIImage(data: capture.jpegData)?.freshVisionJPEG() else {
      throw CaptureError.noImageData
    }
    let id = UUID()
    let name = try images.save(data, id: id)
    let scan = ScanRecord(
      id: id, capturedAt: capture.capturedAt, imageFilename: name, source: capture.source,
      deviceModel: DeviceIdentity.model)
    scan.state = .analyzing
    context.insert(scan)
    try context.save()
    activeScan = scan
    phase = .analyzing
    await analyze(scan, data)
    await syncScan(scan)
  }
  private func analyze(_ scan: ScanRecord, _ data: Data, presentResult: Bool = true) async {
    do {
      let result = try await api.analyze(scanID: scan.id, imageData: data, source: scan.source)
      scan.fruit = result.fruit
      scan.verdict = result.verdict
      scan.reason = result.reason
      scan.issue = result.issue
      scan.confidence = result.confidence
      scan.state = .complete
      if presentResult {
        shopperMessage = result.shopperMessage
        if scan.source == .metaGlasses, let verdict = result.verdict {
          speaker.speak(verdict: verdict, reason: result.reason)
        }
      }
    } catch {
      scan.state = .needsRetry
      scan.lastSyncError = error.localizedDescription
      if presentResult { shopperMessage = error.localizedDescription }
    }
    try? context?.save()
    if presentResult { phase = .result }
  }
  private func syncScan(_ scan: ScanRecord) async {
    guard let data = try? images.data(for: scan.imageFilename) else { return }
    do {
      try await api.syncScan(ScanSyncPayload(scan: scan), imageData: data)
      scan.scanSyncedAt = Date()
      scan.lastSyncError = nil
    } catch { scan.lastSyncError = error.localizedDescription }
    try? context?.save()
  }
  private func syncFeedback(_ scan: ScanRecord) async {
    guard let payload = FeedbackSyncPayload(scan: scan) else { return }
    do {
      try await api.syncFeedback(payload)
      scan.feedbackSyncedAt = Date()
      scan.lastSyncError = nil
    } catch { scan.lastSyncError = error.localizedDescription }
    try? context?.save()
  }
}

extension UIImage {
  fileprivate func freshVisionJPEG() -> Data? {
    let scale = min(1, 1280 / max(size.width, size.height))
    let newSize = CGSize(width: size.width * scale, height: size.height * scale)
    return UIGraphicsImageRenderer(size: newSize).image { _ in
      draw(in: CGRect(origin: .zero, size: newSize))
    }.jpegData(compressionQuality: 0.82)
  }
}
