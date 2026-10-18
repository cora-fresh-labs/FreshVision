import AVFoundation
import Foundation
import Speech
import SwiftUI
import UIKit

enum InspectorVerdict {
  case yes, maybe, no
  var label: String { switch self { case .yes: return "YES"; case .maybe: return "MAYBE"; case .no: return "NO" } }
  var emoji: String { switch self { case .yes: return "✅"; case .maybe: return "🟡"; case .no: return "❌" } }
  var color: String { switch self { case .yes: return "green"; case .maybe: return "yellow"; case .no: return "red" } }
}

struct SessionPhotoItem: Identifiable {
  let id: UUID
  let image: UIImage
  var result: QCResult?
  let capturedAt: Date
}

struct FinalizedReportPayload {
  let timestamp: Date
  let selectedPhotos: [SessionPhotoItem]
  let heroPhoto: SessionPhotoItem?
  let result: QCResult
  let inspectorNotes: String
  let checklist: [InspectorChecklistItem]
  let reportText: String
}

struct InspectorChecklistItem: Identifiable {
  let id: String
  let title: String
  var isChecked: Bool
}

struct SessionRecord: Codable, Identifiable {
  let id: UUID
  let timestamp: Date
  let commodity: String
  let score: String
  let selectedPhotosCount: Int
  let reportText: String
}

@MainActor
class FreshVisionViewModel: ObservableObject {
  @Published var isAnalyzing: Bool = false
  @Published var isBatchAnalyzing: Bool = false
  @Published var latestResult: QCResult?
  @Published var errorMessage: String?
  @Published var pendingVerdict: InspectorVerdict? = nil
  @Published var batchPhotos: [UIImage] = []
  @Published var inspectionHistory: [QCResult] = []
  @Published var isSpeaking: Bool = false
  @Published var sessionCaptured: Set<String> = []

  @Published var sessionPhotos: [SessionPhotoItem] = []
  @Published var selectedPhotoIDs: Set<UUID> = []
  @Published var heroPhotoID: UUID?
  @Published var inspectorNotes: String = ""
  @Published var inspectorChecklist: [InspectorChecklistItem] = [
    InspectorChecklistItem(id: "confirm_grade", title: "Confirm AI grade matches visible condition", isChecked: false),
    InspectorChecklistItem(id: "verify_label", title: "Verify lot/label information", isChecked: false),
    InspectorChecklistItem(id: "confirm_action", title: "Confirm recommended action with SOP", isChecked: false),
    InspectorChecklistItem(id: "attach_photos", title: "Attach representative photos", isChecked: false),
  ]
  @Published var finalizedReportText: String?
  @Published var sessionRecords: [SessionRecord] = []

  // Voice input
  @Published var isListening: Bool = false
  @Published var voiceTranscript: String = ""

  private let claudeService = ClaudeVisionService()
  private let synthesizer = AVSpeechSynthesizer()
  private var synthDelegate: SpeechDelegate?
  private var lastCapturedFrame: UIImage?

  // Speech recognition
  private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private let audioEngine = AVAudioEngine()

  private let recordsKey = "freshvision.session.records.v1"
  private let bridgeEndpoint = UserDefaults.standard.string(forKey: "freshvision.bridge.endpoint")
  private let bridgeToken = UserDefaults.standard.string(forKey: "freshvision.bridge.token")

  init() {
    synthDelegate = SpeechDelegate { [weak self] in
      Task { @MainActor in self?.isSpeaking = false }
    }
    synthesizer.delegate = synthDelegate
    loadRecords()
  }

  // MARK: - Voice Input (SFSpeechRecognizer)

  func startListening() {
    // Request speech recognition permission
    SFSpeechRecognizer.requestAuthorization { [weak self] status in
      Task { @MainActor [weak self] in
        guard let self else { return }
        switch status {
        case .authorized:
          self.beginRecognition()
        case .denied, .restricted:
          self.errorMessage = "Speech recognition permission denied. Enable in Settings > Privacy > Speech Recognition."
        case .notDetermined:
          self.errorMessage = "Speech recognition permission not determined."
        @unknown default:
          self.errorMessage = "Speech recognition unavailable."
        }
      }
    }
  }

  private func beginRecognition() {
    // Stop any existing task
    recognitionTask?.cancel()
    recognitionTask = nil

    // Stop TTS so mic doesn't pick it up
    stopSpeaking()

    // Configure audio session for recording
    let audioSession = AVAudioSession.sharedInstance()
    do {
      try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
      try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      errorMessage = "Audio session error: \(error.localizedDescription)"
      return
    }

    // Create recognition request
    recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
    guard let recognitionRequest else {
      errorMessage = "Unable to create speech recognition request."
      return
    }
    recognitionRequest.shouldReportPartialResults = true

    // Start recognition task
    guard let speechRecognizer, speechRecognizer.isAvailable else {
      errorMessage = "Speech recognizer not available."
      return
    }

    recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
      Task { @MainActor [weak self] in
        guard let self else { return }

        if let result {
          self.voiceTranscript = result.bestTranscription.formattedString

          // Check for voice commands
          let lower = self.voiceTranscript.lowercased()
          if lower.hasSuffix("inspect") || lower.hasSuffix("analyze") {
            // Voice command: trigger inspection
            self.stopListening()
            self.appendTranscriptToNotes()
            // Inspection triggered via voice — caller handles actual inspect call
          }
        }

        if error != nil || (result?.isFinal ?? false) {
          // Recognition ended — append transcript to notes
          if !self.voiceTranscript.isEmpty {
            self.appendTranscriptToNotes()
          }
          if self.isListening {
            // Auto-restart if still in listening mode (continuous dictation)
            self.restartRecognition()
          }
        }
      }
    }

    // Install audio tap
    let inputNode = audioEngine.inputNode
    let recordingFormat = inputNode.outputFormat(forBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
      self?.recognitionRequest?.append(buffer)
    }

    do {
      audioEngine.prepare()
      try audioEngine.start()
      isListening = true
      voiceTranscript = ""
      NSLog("[FreshVision] Voice input started")
    } catch {
      errorMessage = "Audio engine error: \(error.localizedDescription)"
      isListening = false
    }
  }

  private func restartRecognition() {
    // Brief pause then restart for continuous listening
    audioEngine.stop()
    audioEngine.inputNode.removeTap(onBus: 0)
    recognitionRequest = nil
    recognitionTask = nil
    voiceTranscript = ""

    // Small delay before restarting
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self, self.isListening else { return }
      Task { @MainActor in
        self.beginRecognition()
      }
    }
  }

  func stopListening() {
    audioEngine.stop()
    audioEngine.inputNode.removeTap(onBus: 0)
    recognitionRequest?.endAudio()
    recognitionRequest = nil
    recognitionTask?.cancel()
    recognitionTask = nil
    isListening = false

    // Restore audio session for playback (TTS)
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      NSLog("[FreshVision] Audio session restore error: %@", error.localizedDescription)
    }

    NSLog("[FreshVision] Voice input stopped")
  }

  private func appendTranscriptToNotes() {
    let trimmed = voiceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    if inspectorNotes.isEmpty {
      inspectorNotes = trimmed
    } else {
      inspectorNotes += " " + trimmed
    }
    voiceTranscript = ""
    NSLog("[FreshVision] Voice transcript appended to notes: %@", String(trimmed.prefix(100)))
  }

  // MARK: - Batch Verdict Flow

  func addBatchPhoto(_ image: UIImage) {
    let optimized = optimizeForSessionStorage(image)
    batchPhotos.append(optimized)
    registerCapturedPhoto(optimized, id: UUID())
  }

  func submitWithVerdict(_ verdict: InspectorVerdict) async {
    guard !batchPhotos.isEmpty else { return }
    isBatchAnalyzing = true
    pendingVerdict = verdict
    errorMessage = nil
    do {
      let notes = inspectorNotes.trimmingCharacters(in: .whitespacesAndNewlines)
      let commodity = latestResult?.commodity ?? inspectionHistory.last?.commodity
      let result = try await claudeService.analyzeBatch(
        photos: batchPhotos,
        voiceNotes: notes,
        commodity: commodity,
        humanVerdict: verdict.label
      )
      latestResult = result
      inspectionHistory.append(result)
      speakSummary(result.summary)
    } catch {
      errorMessage = error.localizedDescription
      NSLog("[FreshVision] Batch analysis error: %@", error.localizedDescription)
    }
    isBatchAnalyzing = false
  }

  func clearBatch() {
    batchPhotos.removeAll()
    pendingVerdict = nil
  }

  // MARK: - Frame Management

  func updateLatestFrame(_ image: UIImage) {
    lastCapturedFrame = image
  }

  func registerCapturedPhoto(_ image: UIImage, id: UUID) {
    let optimized = optimizeForSessionStorage(image)
    sessionPhotos.append(SessionPhotoItem(id: id, image: optimized, result: nil, capturedAt: Date()))

    let maxSessionPhotos = 20
    if sessionPhotos.count > maxSessionPhotos {
      let overflow = sessionPhotos.count - maxSessionPhotos
      let removed = sessionPhotos.prefix(overflow).map { $0.id }
      sessionPhotos.removeFirst(overflow)
      selectedPhotoIDs.subtract(removed)
      if let hero = heroPhotoID, removed.contains(hero) {
        heroPhotoID = selectedPhotoIDs.first
      }
    }
  }

  func togglePhotoSelection(_ id: UUID) {
    if selectedPhotoIDs.contains(id) {
      selectedPhotoIDs.remove(id)
      if heroPhotoID == id { heroPhotoID = selectedPhotoIDs.first }
    } else {
      selectedPhotoIDs.insert(id)
      if heroPhotoID == nil { heroPhotoID = id }
    }
  }

  func setHeroPhoto(_ id: UUID) {
    guard selectedPhotoIDs.contains(id) else { return }
    heroPhotoID = id
  }

  var canFinalizeReport: Bool { latestResult != nil || inspectionHistory.last != nil }

  private func optimizeForSessionStorage(_ image: UIImage) -> UIImage {
    let maxDimension: CGFloat = 1440
    let size = image.size
    let largest = max(size.width, size.height)
    guard largest > maxDimension else { return image }

    let scale = maxDimension / largest
    let newSize = CGSize(width: size.width * scale, height: size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: newSize)
    return renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: newSize))
    }
  }

  // MARK: - Inspection

  func inspect(using image: UIImage? = nil, sourcePhotoId: UUID? = nil) async {
    guard !isAnalyzing else { return }

    guard ClaudeConfig.isConfigured else {
      errorMessage = "Claude API key not configured. Tap the key icon in the top bar to enter your API key."
      return
    }

    guard let frame = image ?? lastCapturedFrame else {
      errorMessage = "No camera frame available. Make sure the camera is active."
      return
    }

    isAnalyzing = true
    errorMessage = nil

    do {
      let result = try await claudeService.analyzeFrame(frame)
      latestResult = result
      inspectionHistory.append(result)

      if let sop = result.sopCoverage {
        for item in sop.captured { sessionCaptured.insert(item) }
      }

      if let sourcePhotoId,
         let index = sessionPhotos.firstIndex(where: { $0.id == sourcePhotoId }) {
        sessionPhotos[index].result = result
      }

      speakSummary(result.summary)
    } catch {
      errorMessage = error.localizedDescription
      NSLog("[FreshVision] Inspection error: %@", error.localizedDescription)
    }

    isAnalyzing = false
  }

  // MARK: - Report

  func finalizeReportPayload() -> FinalizedReportPayload? {
    guard canFinalizeReport else { return nil }
    guard let result = latestResult ?? inspectionHistory.last else { return nil }

    let selected = sessionPhotos.filter { selectedPhotoIDs.contains($0.id) }
    let hero = selected.first(where: { $0.id == heroPhotoID }) ?? selected.first
    let notes = inspectorNotes.trimmingCharacters(in: .whitespacesAndNewlines)
    let text = formatFinalizedReportText(
      result: result,
      selectedPhotos: selected,
      heroPhotoID: hero?.id,
      inspectorNotes: notes,
      checklist: inspectorChecklist
    )
    finalizedReportText = text

    let record = SessionRecord(
      id: UUID(),
      timestamp: Date(),
      commodity: result.commodity?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Unknown",
      score: result.overallScore,
      selectedPhotosCount: selected.count,
      reportText: text
    )
    persistRecord(record)

    let payload = FinalizedReportPayload(
      timestamp: Date(),
      selectedPhotos: selected,
      heroPhoto: hero,
      result: result,
      inspectorNotes: notes,
      checklist: inspectorChecklist,
      reportText: text
    )

    Task { await uploadFinalizedReportToBridge(payload) }

    return payload
  }

  private func uploadFinalizedReportToBridge(_ payload: FinalizedReportPayload) async {
    guard let bridgeEndpoint,
          let bridgeToken,
          !bridgeEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !bridgeToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let url = URL(string: bridgeEndpoint) else { return }

    let photos = payload.selectedPhotos.enumerated().compactMap { index, item -> [String: Any]? in
      guard let data = item.image.jpegData(compressionQuality: 0.72) else { return nil }
      return [
        "photoId": item.id.uuidString,
        "index": index + 1,
        "capturedAt": ISO8601DateFormatter().string(from: item.capturedAt),
        "isHero": item.id == payload.heroPhoto?.id,
        "imageBase64": data.base64EncodedString(),
      ]
    }

    let dedupeSource = payload.selectedPhotos.map { $0.id.uuidString }.joined(separator: ":") + ":" + payload.result.overallScore
    let idempotencyKey = "ios-\(abs(dedupeSource.hashValue))"

    let body: [String: Any] = [
      "source": "camera_access_glasses",
      "idempotencyKey": idempotencyKey,
      "capturedAt": ISO8601DateFormatter().string(from: payload.timestamp),
      "commodity": payload.result.commodity ?? "unknown",
      "overallScore": payload.result.overallScore,
      "recommendedAction": payload.result.recommendedAction,
      "summary": payload.result.summary,
      "inspectorNotes": payload.inspectorNotes,
      "manualChecklist": payload.checklist.map { ["id": $0.id, "title": $0.title, "isChecked": $0.isChecked] },
      "reportText": payload.reportText,
      "photos": photos,
    ]

    guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(bridgeToken, forHTTPHeaderField: "X-FreshVision-Bridge-Token")
    request.httpBody = bodyData

    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
        NSLog("[FreshVision] Bridge ingest failed with status %d", http.statusCode)
      }
    } catch {
      NSLog("[FreshVision] Bridge ingest error: %@", error.localizedDescription)
    }

  }

  private func formatFinalizedReportText(
    result: QCResult,
    selectedPhotos: [SessionPhotoItem],
    heroPhotoID: UUID?,
    inspectorNotes: String,
    checklist: [InspectorChecklistItem]
  ) -> String {
    var text = formatReportText(result)
    let heroText: String
    if let heroPhotoID,
       let heroIndex = selectedPhotos.firstIndex(where: { $0.id == heroPhotoID }) {
      heroText = "Hero Photo: #\(heroIndex + 1)"
    } else {
      heroText = "Hero Photo: #1"
    }

    text += "\n\nSelected Photos: \(selectedPhotos.count)\n\(heroText)"
    text += "\n\nInspector Notes:\n\(inspectorNotes.isEmpty ? "No notes provided." : inspectorNotes)"

    text += "\n\nManual Checklist:"
    for item in checklist {
      text += "\n\(item.isChecked ? "✅" : "⬜") \(item.title)"
    }

    if !inspectionHistory.isEmpty {
      text += "\n\nRecent Session Scores:"
      for result in inspectionHistory.suffix(5) {
        let commodity = result.commodity?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Unknown"
        text += "\n• \(commodity): \(result.overallScore)"
      }
    }

    return text
  }

  // MARK: - PDF / Save

  /// Generate a professional QC report PDF matching Costa/FPG assessment format.
  /// Layout: Page 1 = header + metadata + quality summary + variables + notes
  ///         Page 2 = 3-tier defect breakdown (critical/major/minor)
  ///         Pages 3+ = captioned photos in 2-up grid
  func generateReportPDFData(text: String) -> Data {
    let result = latestResult ?? inspectionHistory.last
    // If user selected specific photos, use those. Otherwise include ALL session photos.
    let photos = selectedPhotoIDs.isEmpty ? sessionPhotos : sessionPhotos.filter { selectedPhotoIDs.contains($0.id) }
    return generateCostaStylePDF(result: result, selectedPhotos: photos)
  }

  private func generateCostaStylePDF(result: QCResult?, selectedPhotos: [SessionPhotoItem]) -> Data {
    let meta = [kCGPDFContextCreator: "FreshVision", kCGPDFContextAuthor: "FreshVision QC"]
    let format = UIGraphicsPDFRendererFormat()
    format.documentInfo = meta as [String: Any]
    let pageW: CGFloat = 612
    let pageH: CGFloat = 792
    let pageRect = CGRect(x: 0, y: 0, width: pageW, height: pageH)
    let margin: CGFloat = 36
    let contentW = pageW - margin * 2
    let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

    let commodity = result?.commodity?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Unknown"
    let variety = result?.variety ?? "—"
    let score = result?.overallScore.uppercased() ?? "—"
    let action = result?.recommendedAction.replacingOccurrences(of: "_", with: " ").uppercased() ?? "—"
    let summary = result?.summary ?? ""
    let defects = result?.defects ?? []

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "dd/MM/yy h:mm a"
    let dateStr = dateFormatter.string(from: Date())

    // Fonts
    let titleFont = UIFont.systemFont(ofSize: 18, weight: .bold)
    let headerFont = UIFont.systemFont(ofSize: 11, weight: .bold)
    let bodyFont = UIFont.systemFont(ofSize: 10, weight: .regular)
    let smallFont = UIFont.systemFont(ofSize: 9, weight: .regular)
    let smallBold = UIFont.systemFont(ofSize: 9, weight: .bold)

    // Colors
    let greenBg = UIColor(red: 0.56, green: 0.93, blue: 0.56, alpha: 1.0)
    let redBg = UIColor(red: 0.93, green: 0.56, blue: 0.56, alpha: 1.0)
    let amberBg = UIColor(red: 0.98, green: 0.85, blue: 0.37, alpha: 1.0)
    let headerBg = UIColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 1.0)
    let borderColor = UIColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1.0)

    func drawText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor = .black, alignment: NSTextAlignment = .left) {
      let para = NSMutableParagraphStyle()
      para.alignment = alignment
      para.lineBreakMode = .byWordWrapping
      let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
      (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    func drawTableRow(y: inout CGFloat, label: String, value: String, labelWidth: CGFloat = contentW * 0.55, isHeader: Bool = false) {
      let rowH: CGFloat = 18
      let rect = CGRect(x: margin, y: y, width: contentW, height: rowH)
      if isHeader { headerBg.setFill(); UIBezierPath(rect: rect).fill() }
      borderColor.setStroke()
      UIBezierPath(rect: rect).stroke()
      drawText(label, in: CGRect(x: margin + 4, y: y + 2, width: labelWidth - 8, height: rowH - 4), font: isHeader ? smallBold : smallFont)
      drawText(value, in: CGRect(x: margin + labelWidth, y: y + 2, width: contentW - labelWidth - 4, height: rowH - 4), font: isHeader ? smallBold : smallFont, alignment: .right)
      y += rowH
    }

    func drawMetadataGrid(y: inout CGFloat, pairs: [(String, String, String, String)]) {
      let rowH: CGFloat = 18
      let col1LabelW: CGFloat = 90
      let col1ValueW: CGFloat = contentW / 2 - col1LabelW
      let col2LabelW: CGFloat = 90
      for (l1, v1, l2, v2) in pairs {
        let x1 = margin
        let x2 = margin + contentW / 2
        borderColor.setStroke()
        UIBezierPath(rect: CGRect(x: x1, y: y, width: contentW, height: rowH)).stroke()
        drawText(l1, in: CGRect(x: x1 + 4, y: y + 2, width: col1LabelW - 8, height: rowH - 4), font: smallBold)
        drawText(v1, in: CGRect(x: x1 + col1LabelW, y: y + 2, width: col1ValueW - 4, height: rowH - 4), font: smallFont)
        drawText(l2, in: CGRect(x: x2 + 4, y: y + 2, width: col2LabelW - 8, height: rowH - 4), font: smallBold)
        drawText(v2, in: CGRect(x: x2 + col2LabelW, y: y + 2, width: contentW / 2 - col2LabelW - 4, height: rowH - 4), font: smallFont)
        y += rowH
      }
    }

    func drawPageNumber(_ context: UIGraphicsPDFRendererContext, pageNum: Int, totalPages: Int) {
      let text = "Page \(pageNum) of \(totalPages)"
      drawText(text, in: CGRect(x: pageW - 140, y: pageH - 30, width: 100, height: 14), font: smallFont, alignment: .right)
    }

    // Calculate total pages
    let photoPagesNeeded = selectedPhotos.isEmpty ? 0 : Int(ceil(Double(selectedPhotos.count) / 6.0))
    let totalPages = 2 + photoPagesNeeded

    return renderer.pdfData { context in
      var pageNum = 1

      // ═══════════════════════════════════════════════════════════════
      // PAGE 1: Header + Metadata + Quality Summary + Variables + Notes
      // ═══════════════════════════════════════════════════════════════
      context.beginPage()
      var y: CGFloat = margin

      // Title header
      drawText("QA Assessment", in: CGRect(x: margin, y: y, width: contentW, height: 24), font: titleFont, alignment: .center)
      y += 26
      drawText("FreshVision Automated QC Report", in: CGRect(x: margin, y: y, width: contentW, height: 16), font: UIFont.systemFont(ofSize: 11, weight: .medium), color: .darkGray, alignment: .center)
      y += 24

      // Separator
      borderColor.setStroke()
      let sep = UIBezierPath()
      sep.move(to: CGPoint(x: margin, y: y))
      sep.addLine(to: CGPoint(x: margin + contentW, y: y))
      sep.lineWidth = 1
      sep.stroke()
      y += 10

      // Metadata grid
      let origin = result?.originDetected ?? "—"
      let supplier = result?.supplierDetected ?? "—"
      drawMetadataGrid(y: &y, pairs: [
        ("Commodity:", commodity, "Date/Time:", dateStr),
        ("Variety:", variety, "Inspector:", "FreshVision AI"),
        ("Origin:", origin, "Supplier:", supplier),
        ("Score:", score, "Action:", action),
        ("Photos:", "\(selectedPhotos.count)", "Method:", "Claude Vision + CV"),
      ])
      y += 10

      // Result badge
      let resultBg = score == "GREEN" ? greenBg : (score == "RED" ? redBg : amberBg)
      let badgeRect = CGRect(x: margin, y: y, width: 80, height: 22)
      resultBg.setFill()
      UIBezierPath(roundedRect: badgeRect, cornerRadius: 4).fill()
      drawText(score == "GREEN" ? "Pass" : (score == "RED" ? "Fail" : "Hold"), in: CGRect(x: margin + 4, y: y + 3, width: 72, height: 16), font: UIFont.systemFont(ofSize: 12, weight: .bold), color: .black, alignment: .center)
      y += 30

      // Quality Summary table
      drawText("Quality Summary", in: CGRect(x: margin, y: y, width: contentW, height: 16), font: headerFont)
      y += 18

      let criticalDefects = defects.filter { $0.severity.lowercased() == "critical" }
      let majorDefects = defects.filter { $0.severity.lowercased() == "major" }
      let minorDefects = defects.filter { $0.severity.lowercased() == "minor" }
      let totalPct = defects.compactMap { $0.estimatedPercentage }.reduce(0, +)

      drawTableRow(y: &y, label: "QA", value: String(format: "%.1f%%", totalPct), isHeader: true)
      drawTableRow(y: &y, label: "Critical Defects", value: String(format: "%.1f%%", criticalDefects.compactMap { $0.estimatedPercentage }.reduce(0, +)))
      drawTableRow(y: &y, label: "Major Defects", value: String(format: "%.1f%%", majorDefects.compactMap { $0.estimatedPercentage }.reduce(0, +)))
      drawTableRow(y: &y, label: "Minor Defects", value: String(format: "%.1f%%", minorDefects.compactMap { $0.estimatedPercentage }.reduce(0, +)))
      y += 12

      // Notes
      drawText("Notes:", in: CGRect(x: margin, y: y, width: contentW, height: 14), font: headerFont)
      y += 16
      let notesText = inspectorNotes.isEmpty ? summary : inspectorNotes + "\n\nAI Summary: " + summary
      drawText(notesText, in: CGRect(x: margin, y: y, width: contentW, height: 80), font: bodyFont)
      y += 86

      // Variables & Measurements
      if y < pageH - 200 {
        drawText("Variables and Measurements", in: CGRect(x: margin, y: y, width: contentW, height: 16), font: headerFont)
        y += 18

        drawTableRow(y: &y, label: "AI Confidence", value: result?.overallScore ?? "—")
        drawTableRow(y: &y, label: "Commodity Detected", value: commodity)
        drawTableRow(y: &y, label: "Variety Detected", value: variety)
        drawTableRow(y: &y, label: "General Appearance", value: score == "GREEN" ? "Meets specification" : "Below specification")

        if let flags = result?.complianceFlags, !flags.isEmpty {
          let flagsStr = flags.map { $0.replacingOccurrences(of: "_", with: " ").capitalized }.joined(separator: ", ")
          drawTableRow(y: &y, label: "Compliance Flags", value: flagsStr)
        }

        // Checklist items
        for item in inspectorChecklist {
          drawTableRow(y: &y, label: item.title, value: item.isChecked ? "Yes" : "No")
        }
      }

      drawPageNumber(context, pageNum: pageNum, totalPages: totalPages)
      pageNum += 1

      // ═══════════════════════════════════════════════════════════════
      // PAGE 2: 3-tier Defect Breakdown
      // ═══════════════════════════════════════════════════════════════
      context.beginPage()
      y = margin

      // Inline defect tier rendering (avoids nested function actor-isolation errors)
      for (tierName, tierDefects) in [
        ("Defects - Critical", criticalDefects),
        ("Defects - Major", majorDefects),
        ("Defects - Minor", minorDefects),
      ] {
        let tierCount = tierDefects.count
        let tierPct = tierDefects.compactMap { $0.estimatedPercentage }.reduce(0, +)
        drawTableRow(y: &y, label: tierName, value: "Total Count: \(tierCount)     Total: \(String(format: "%.2f%%", tierPct))", isHeader: true)

        if tierDefects.isEmpty {
          let tierLabel = tierName.lowercased().replacingOccurrences(of: "defects - ", with: "")
          drawTableRow(y: &y, label: "No \(tierLabel) defects detected", value: "0     0.00%")
        } else {
          for defect in tierDefects {
            let name = defect.type.replacingOccurrences(of: "_", with: " ").capitalized
            let pct = defect.estimatedPercentage ?? 0
            let location = defect.location.replacingOccurrences(of: "_", with: " ")
            drawTableRow(y: &y, label: "\(name) — \(location)", value: "1     \(String(format: "%.2f%%", pct))")
          }
        }
        y += 16
      }

      drawPageNumber(context, pageNum: pageNum, totalPages: totalPages)
      pageNum += 1

      // ═══════════════════════════════════════════════════════════════
      // PAGES 3+: Captioned Photos (2-up grid per row, 3 rows per page = 6 photos)
      // ═══════════════════════════════════════════════════════════════
      if !selectedPhotos.isEmpty {
        let photoW = (contentW - 20) / 2  // Two columns with gap
        let photoH: CGFloat = 180
        let captionH: CGFloat = 20
        let rowSpacing: CGFloat = 30
        let photosPerPage = 6

        for pageStart in stride(from: 0, to: selectedPhotos.count, by: photosPerPage) {
          context.beginPage()
          y = margin

          if pageStart == 0 {
            drawText("Photos", in: CGRect(x: margin, y: y, width: contentW, height: 22), font: titleFont)
            y += 30
          }

          let pageEnd = min(pageStart + photosPerPage, selectedPhotos.count)
          for i in stride(from: pageStart, to: pageEnd, by: 2) {
            // Left photo
            let leftPhoto = selectedPhotos[i]
            let leftRect = CGRect(x: margin + 20, y: y, width: photoW - 20, height: photoH)
            leftPhoto.image.draw(in: leftRect)
            borderColor.setStroke()
            UIBezierPath(rect: leftRect).stroke()

            let leftCaption = leftPhoto.result?.defects.first.map {
              $0.type.replacingOccurrences(of: "_", with: " ")
            } ?? (leftPhoto.id == heroPhotoID ? "hero photo" : "inspection photo \(i + 1)")
            drawText(leftCaption, in: CGRect(x: margin + 20, y: y + photoH + 4, width: photoW - 20, height: captionH), font: smallFont, alignment: .center)

            // Right photo (if exists)
            if i + 1 < pageEnd {
              let rightPhoto = selectedPhotos[i + 1]
              let rightRect = CGRect(x: margin + contentW / 2 + 10, y: y, width: photoW - 20, height: photoH)
              rightPhoto.image.draw(in: rightRect)
              UIBezierPath(rect: rightRect).stroke()

              let rightCaption = rightPhoto.result?.defects.first.map {
                $0.type.replacingOccurrences(of: "_", with: " ")
              } ?? "inspection photo \(i + 2)"
              drawText(rightCaption, in: CGRect(x: margin + contentW / 2 + 10, y: y + photoH + 4, width: photoW - 20, height: captionH), font: smallFont, alignment: .center)
            }

            y += photoH + captionH + rowSpacing
          }

          drawPageNumber(context, pageNum: pageNum, totalPages: totalPages)
          pageNum += 1
        }
      }
    }
  }

  func saveReportToDocuments(text: String, pdfData: Data) throws -> URL {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let stamp = formatter.string(from: Date())
    let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let txtURL = directory.appendingPathComponent("FreshVision-Report-\(stamp).txt")
    let pdfURL = directory.appendingPathComponent("FreshVision-Report-\(stamp).pdf")
    try text.data(using: .utf8)?.write(to: txtURL)
    try pdfData.write(to: pdfURL)
    return pdfURL
  }

  func saveSelectedPhotosToLibrary() {
    let photos = sessionPhotos.filter { selectedPhotoIDs.contains($0.id) }
    for photo in photos {
      UIImageWriteToSavedPhotosAlbum(photo.image, nil, nil, nil)
    }
  }

  // MARK: - TTS

  func speakSummary(_ text: String) {
    // Stop any active mic/listening to avoid audio session conflict
    if isListening { stopListening() }

    synthesizer.stopSpeaking(at: .immediate)

    // Ensure audio session is set for playback before speaking
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      NSLog("[FreshVision] TTS audio session setup error: %@", error.localizedDescription)
    }

    let utterance = AVSpeechUtterance(string: text)
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    utterance.voice = AVSpeechSynthesisVoice(language: "en-AU")
    isSpeaking = true
    synthesizer.speak(utterance)
  }

  func stopSpeaking() {
    synthesizer.stopSpeaking(at: .immediate)
    isSpeaking = false
  }

  // MARK: - Utilities

  func copyResultJSON() -> Bool {
    guard let result = latestResult else { return false }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(result),
          let json = String(data: data, encoding: .utf8) else { return false }
    UIPasteboard.general.string = json
    return true
  }

  func formatReportText(_ result: QCResult) -> String {
    let scoreEmoji: String
    switch result.overallScore.uppercased() {
    case "GREEN": scoreEmoji = "🟢"
    case "AMBER": scoreEmoji = "🟡"
    case "RED": scoreEmoji = "🔴"
    default: scoreEmoji = "⚪"
    }

    let actionEmoji: String
    switch result.recommendedAction.lowercased() {
    case "accept": actionEmoji = "✅"
    case "hold_for_regrade": actionEmoji = "⏸️"
    case "downgrade": actionEmoji = "⬇️"
    case "reject": actionEmoji = "❌"
    case "return_to_vendor": actionEmoji = "🔙"
    default: actionEmoji = "❓"
    }

    var lines: [String] = []
    let commodity = result.commodity?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Unknown"
    lines.append("🍊 FreshVision QC Report")
    lines.append("━━━━━━━━━━━━━━━━━━━━━━━━")
    lines.append("Score: \(scoreEmoji) \(result.overallScore)")
    lines.append("Action: \(actionEmoji) \(result.recommendedAction.replacingOccurrences(of: "_", with: " ").uppercased())")
    lines.append("Commodity: \(commodity)")
    if let variety = result.variety { lines.append("Variety: \(variety)") }

    if !result.complianceFlags.isEmpty {
      lines.append("")
      lines.append("⚠️ Compliance Flags:")
      for flag in result.complianceFlags {
        lines.append("• \(flag.replacingOccurrences(of: "_", with: " ").capitalized)")
      }
    }

    if !result.defects.isEmpty {
      lines.append("")
      lines.append("Defects Found:")
      for defect in result.defects {
        let pctStr = defect.estimatedPercentage.map { " (\(Int($0))%)" } ?? ""
        lines.append("• \(defect.severity.capitalized) \(defect.type.replacingOccurrences(of: "_", with: " "))\(pctStr) — \(defect.location.replacingOccurrences(of: "_", with: " "))")
      }
    }

    lines.append("")
    lines.append("Summary: \(result.summary)")

    if let origin = result.originDetected { lines.append("📍 Origin: \(origin)") }
    if let supplier = result.supplierDetected { lines.append("🏢 Supplier: \(supplier)") }

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    lines.append("📅 \(formatter.string(from: Date()))")
    lines.append("━━━━━━━━━━━━━━━━━━━━━━━━")
    lines.append("Generated by FreshVision")

    return lines.joined(separator: "\n")
  }

  func formatSessionSummary() -> String {
    guard !inspectionHistory.isEmpty else { return "" }
    var lines: [String] = []
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"

    lines.append("🍇 FreshVision Session Report")
    lines.append("Date: \(formatter.string(from: Date()))")
    lines.append("Inspections: \(inspectionHistory.count)")

    for (index, result) in inspectionHistory.enumerated() {
      let commodity = result.commodity?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Unknown"
      lines.append("\(index + 1). \(commodity) — \(result.overallScore)")
    }

    return lines.joined(separator: "\n")
  }

  func clearSession() {
    latestResult = nil
    inspectionHistory.removeAll()
    sessionCaptured.removeAll()
    sessionPhotos.removeAll()
    selectedPhotoIDs.removeAll()
    heroPhotoID = nil
    inspectorNotes = ""
    inspectorChecklist = [
      InspectorChecklistItem(id: "confirm_grade", title: "Confirm AI grade matches visible condition", isChecked: false),
      InspectorChecklistItem(id: "verify_label", title: "Verify lot/label information", isChecked: false),
      InspectorChecklistItem(id: "confirm_action", title: "Confirm recommended action with SOP", isChecked: false),
      InspectorChecklistItem(id: "attach_photos", title: "Attach representative photos", isChecked: false),
    ]
    finalizedReportText = nil
    errorMessage = nil
    stopSpeaking()
    stopListening()
  }

  private func persistRecord(_ record: SessionRecord) {
    sessionRecords.insert(record, at: 0)
    if sessionRecords.count > 50 { sessionRecords = Array(sessionRecords.prefix(50)) }
    if let data = try? JSONEncoder().encode(sessionRecords) {
      UserDefaults.standard.set(data, forKey: recordsKey)
    }
  }

  private func loadRecords() {
    guard let data = UserDefaults.standard.data(forKey: recordsKey),
          let records = try? JSONDecoder().decode([SessionRecord].self, from: data) else { return }
    sessionRecords = records
  }
}

private class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
  let onFinish: () -> Void

  init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { onFinish() }
  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { onFinish() }
}
