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
  private let api: FreshVisionAPI
  private let images: ImageStore?
  let speaker = VerdictSpeaker()
  private var context: ModelContext?
  private var isSyncing = false
  private var analysesInFlight: Set<UUID> = []
  private var scanUploadsInFlight: Set<UUID> = []
  private var feedbackUploadsInFlight: Set<UUID> = []

  init(api: FreshVisionAPI = FreshVisionAPI(), images: ImageStore? = try? ImageStore()) {
    self.api = api
    self.images = images
  }

  func attach(_ context: ModelContext) {
    self.context = context
    Task { await syncPending() }
  }
  func syncPending() async {
    guard !isSyncing else { return }
    isSyncing = true
    defer { isSyncing = false }
    guard let context,
      let scans = try? context.fetch(
        FetchDescriptor<ScanRecord>(sortBy: [SortDescriptor(\.capturedAt)]))
    else { return }
    for scan in scans where scan.pendingDeletion { await finishDeletion(scan) }
    for scan in scans where !scan.pendingDeletion && scan.scanSyncedAt == nil {
      if scan.state == .captured || scan.state == .analyzing {
        if analysesInFlight.contains(scan.id) { continue }
        guard let data = try? images?.data(for: scan.imageFilename) else { continue }
        await analyze(scan, data, presentResult: false)
      }
      await syncScan(scan)
    }
    for scan in scans
    where !scan.pendingDeletion && scan.feedback != nil && scan.feedbackSyncedAt == nil {
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
    speaker.stop()
    activeScan = nil
    shopperMessage = nil
    showsFeedback = true
    phase = .camera
  }
  func dismissFeedback() { showsFeedback = false }
  func importPhoto(_ data: Data) async {
    guard phase == .camera else { return }
    phase = .capturing
    shopperMessage = nil
    do {
      try await process(.init(jpegData: data, source: .iPhone, capturedAt: Date()))
    } catch {
      phase = .camera
      shopperMessage = error.localizedDescription
    }
  }
  func show(_ scan: ScanRecord) {
    speaker.stop()
    activeScan = scan
    shopperMessage = scan.issue.flatMap { _ in
      FruitAnalysisResponse(supported: false, fruit: nil, verdict: nil, reason: scan.reason ?? "",
                            issue: scan.issue, confidence: scan.confidence ?? 0).shopperMessage
    } ?? scan.lastSyncError
    showsFeedback = scan.feedback == nil
    phase = .result
  }
  func speak(_ scan: ScanRecord) async {
    guard scan.verdict != nil, !scan.pendingDeletion else { return }
    if scan.scanSyncedAt == nil { await syncScan(scan) }
    guard activeScan?.id == scan.id, phase == .result else { return }
    speaker.speak(scanID: scan.id, api: api)
  }
  func image(for scan: ScanRecord) -> UIImage? {
    guard let path = images?.url(for: scan.imageFilename).path else { return nil }
    return UIImage(contentsOfFile: path)
  }
  func vote(_ choice: FeedbackChoice, for value: ScanRecord? = nil) {
    guard let context, let scan = value ?? activeScan else { return }
    let priorFeedback = scan.feedback
    let priorDate = scan.feedbackAt
    let priorSync = scan.feedbackSyncedAt
    scan.feedback = choice
    scan.feedbackAt = Date()
    scan.feedbackSyncedAt = nil
    do {
      try context.save()
    } catch {
      scan.feedback = priorFeedback
      scan.feedbackAt = priorDate
      scan.feedbackSyncedAt = priorSync
      shopperMessage = "Your vote did not save. Please try again."
      return
    }
    showsFeedback = false
    Task { await syncFeedback(scan) }
  }
  func retry(_ scan: ScanRecord) async {
    guard phase != .analyzing, phase != .capturing else { return }
    guard let data = try? images?.data(for: scan.imageFilename) else { return }
    speaker.stop()
    speaker.invalidate(scan.id)
    activeScan = scan
    scan.scanSyncedAt = nil
    phase = .analyzing
    await analyze(scan, data)
    await syncScan(scan)
    if scan.verdict != nil { await speak(scan) }
  }
  func delete(_ scan: ScanRecord) async {
    guard let context else { return }
    do {
      scan.pendingDeletion = true
      try context.save()
      if activeScan?.id == scan.id { newScan() }
      speaker.invalidate(scan.id)
    } catch {
      shopperMessage = "That scan could not be deleted. Check your connection and try again."
      return
    }
    await finishDeletion(scan)
  }

  private func process(_ capture: CapturedFruitImage) async throws {
    guard let context else { throw FreshVisionAPIError.invalidResponse }
    guard let data = UIImage(data: capture.jpegData)?.freshVisionJPEG() else {
      throw CaptureError.noImageData
    }
    let id = UUID()
    guard let images else { throw CaptureError.storageUnavailable }
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
    if scan.verdict != nil { await speak(scan) }
  }
  private func analyze(_ scan: ScanRecord, _ data: Data, presentResult: Bool = true) async {
    guard analysesInFlight.insert(scan.id).inserted else { return }
    defer { analysesInFlight.remove(scan.id) }
    do {
      let result = try await api.analyze(scanID: scan.id, imageData: data, source: scan.source)
      scan.fruit = result.fruit
      scan.verdict = result.verdict
      scan.reason = result.reason
      scan.issue = result.issue
      scan.confidence = result.confidence
      scan.state = .complete
      scan.lastSyncError = nil
      if presentResult {
        shopperMessage = result.shopperMessage
      }
    } catch {
      scan.state = .needsRetry
      scan.fruit = nil
      scan.verdict = nil
      scan.reason = nil
      scan.issue = nil
      scan.confidence = nil
      scan.lastSyncError = error.localizedDescription
      if presentResult { shopperMessage = error.localizedDescription }
    }
    do {
      try context?.save()
    } catch {
      scan.lastSyncError = "The result is safe in this session but could not be stored."
      if presentResult { shopperMessage = "The result could not be stored. Please try this photo again." }
    }
    if presentResult { phase = .result }
  }
  private func syncScan(_ scan: ScanRecord) async {
    guard !scan.pendingDeletion else { return }
    guard scanUploadsInFlight.insert(scan.id).inserted else { return }
    defer { scanUploadsInFlight.remove(scan.id) }
    guard let data = try? images?.data(for: scan.imageFilename) else { return }
    do {
      try await api.syncScan(ScanSyncPayload(scan: scan), imageData: data)
      guard !scan.pendingDeletion else { return }
      scan.scanSyncedAt = Date()
      scan.lastSyncError = nil
    } catch { scan.lastSyncError = error.localizedDescription }
    do { try context?.save() } catch {
      scan.scanSyncedAt = nil
      scan.lastSyncError = "The upload receipt could not be stored."
    }
  }
  private func syncFeedback(_ scan: ScanRecord) async {
    guard !scan.pendingDeletion else { return }
    guard feedbackUploadsInFlight.insert(scan.id).inserted else { return }
    defer { feedbackUploadsInFlight.remove(scan.id) }
    guard let payload = FeedbackSyncPayload(scan: scan) else { return }
    do {
      try await api.syncFeedback(payload)
      scan.feedbackSyncedAt = Date()
      scan.lastSyncError = nil
    } catch { scan.lastSyncError = error.localizedDescription }
    do { try context?.save() } catch {
      scan.feedbackSyncedAt = nil
      scan.lastSyncError = "The feedback upload receipt could not be stored."
    }
  }

  private func finishDeletion(_ scan: ScanRecord) async {
    guard scan.pendingDeletion, let context else { return }
    do {
      try images?.delete(scan.imageFilename)
      for _ in 0..<200 where scanUploadsInFlight.contains(scan.id) {
        try await Task.sleep(for: .milliseconds(100))
      }
      guard !scanUploadsInFlight.contains(scan.id) else { throw FreshVisionAPIError.timedOut }
      try await api.deleteScan(id: scan.id)
      context.delete(scan)
      try context.save()
    } catch {
      scan.lastSyncError = "Deletion will retry when FreshVision is online."
      try? context.save()
    }
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
