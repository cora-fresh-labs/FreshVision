import Foundation
import UIKit

enum ClaudeServiceError: Error, LocalizedError {
  case notConfigured
  case invalidImage
  case networkError(String)
  case apiError(Int, String)
  case decodingError(String)

  var errorDescription: String? {
    switch self {
    case .notConfigured:
      return "Claude API key not configured. Enter your key in Settings (key icon in top bar)."
    case .invalidImage:
      return "Failed to encode image as JPEG."
    case .networkError(let msg):
      return "Network error: \(msg)"
    case .apiError(let code, let msg):
      return "API error (HTTP \(code)): \(msg)"
    case .decodingError(let msg):
      return "Failed to parse QC result: \(msg)"
    }
  }
}

@MainActor
class ClaudeVisionService: ObservableObject {
  @Published var isAnalyzing: Bool = false

  private let session: URLSession

  init() {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 60
    self.session = URLSession(configuration: config)
  }

  func analyzeFrame(_ image: UIImage) async throws -> QCResult {
    guard ClaudeConfig.isConfigured else {
      throw ClaudeServiceError.notConfigured
    }

    guard let jpegData = image.jpegData(compressionQuality: ClaudeConfig.videoJPEGQuality) else {
      throw ClaudeServiceError.invalidImage
    }

    isAnalyzing = true
    defer { isAnalyzing = false }

    let base64Image = jpegData.base64EncodedString()

    guard let url = URL(string: ClaudeConfig.baseURL) else {
      throw ClaudeServiceError.networkError("Invalid API URL")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(ClaudeConfig.apiKey, forHTTPHeaderField: "x-api-key")
    request.setValue(ClaudeConfig.apiVersion, forHTTPHeaderField: "anthropic-version")
    request.setValue("application/json", forHTTPHeaderField: "content-type")

    let body: [String: Any] = [
      "model": ClaudeConfig.model,
      "max_tokens": ClaudeConfig.maxTokens,
      "system": ClaudeConfig.systemPrompt,
      "messages": [
        [
          "role": "user",
          "content": [
            [
              "type": "image",
              "source": [
                "type": "base64",
                "media_type": "image/jpeg",
                "data": base64Image
              ]
            ],
            [
              "type": "text",
              "text": "Inspect this produce and provide your QC assessment."
            ]
          ]
        ]
      ]
    ]

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    } catch {
      throw ClaudeServiceError.networkError("Failed to serialize request: \(error.localizedDescription)")
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw ClaudeServiceError.networkError(error.localizedDescription)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw ClaudeServiceError.networkError("Invalid response type")
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      let bodyStr = String(data: data, encoding: .utf8) ?? "no body"
      NSLog("[Claude] API error: HTTP %d - %@", httpResponse.statusCode, String(bodyStr.prefix(500)))
      throw ClaudeServiceError.apiError(httpResponse.statusCode, String(bodyStr.prefix(200)))
    }

    // Parse the Messages API response to extract the text content
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let content = json["content"] as? [[String: Any]],
          let firstBlock = content.first,
          let text = firstBlock["text"] as? String else {
      let raw = String(data: data, encoding: .utf8) ?? "empty"
      throw ClaudeServiceError.decodingError("Could not extract text from response: \(String(raw.prefix(200)))")
    }

    NSLog("[Claude] Raw response: %@", String(text.prefix(300)))

    // Extract JSON from the response text (Claude may wrap it in markdown code fences)
    let jsonString = extractJSON(from: text)

    guard let jsonData = jsonString.data(using: .utf8) else {
      throw ClaudeServiceError.decodingError("Could not convert response text to data")
    }

    do {
      let decoder = JSONDecoder()
      let result = try decoder.decode(QCResult.self, from: jsonData)
      return result
    } catch {
      NSLog("[Claude] Decode error: %@ from text: %@", error.localizedDescription, String(jsonString.prefix(500)))
      throw ClaudeServiceError.decodingError(error.localizedDescription)
    }
  }

  // MARK: - Batch Analysis (all photos + voice notes + spec in one call)

  func analyzeBatch(photos: [UIImage], voiceNotes: String, commodity: String?, humanVerdict: String) async throws -> QCResult {
    guard ClaudeConfig.isConfigured else { throw ClaudeServiceError.notConfigured }
    guard !photos.isEmpty else { throw ClaudeServiceError.invalidImage }

    isAnalyzing = true
    defer { isAnalyzing = false }

    // Build image content blocks
    var contentBlocks: [[String: Any]] = []
    for photo in photos.prefix(10) {
      guard let jpegData = photo.jpegData(compressionQuality: 0.85) else { continue }
      contentBlocks.append([
        "type": "image",
        "source": ["type": "base64", "media_type": "image/jpeg", "data": jpegData.base64EncodedString()]
      ])
    }

    // Add text prompt
    let notesText = voiceNotes.isEmpty ? "No verbal notes." : voiceNotes
    contentBlocks.append([
      "type": "text",
      "text": "Inspector verdict: \(humanVerdict)\nInspector notes: \(notesText)\n\nAll \(photos.count) photos above are from the same QC inspection event. Assess them collectively and return your QC assessment JSON."
    ])

    // Load commodity spec if available
    var systemPrompt = ClaudeConfig.systemPrompt
    if let commodity = commodity?.lowercased() {
      let specFile: String?
      if commodity.contains("grape") { specFile = "spec_grapes" }
      else if ["citrus","orange","lemon","lime","mandarin","grapefruit","navel"].contains(where: { commodity.contains($0) }) { specFile = "spec_citrus" }
      else if commodity.contains("blueberr") { specFile = "spec_blueberries" }
      else { specFile = nil }
      if let specFile, let url = Bundle.main.url(forResource: specFile, withExtension: "json"),
         let specData = try? Data(contentsOf: url), let specStr = String(data: specData, encoding: .utf8) {
        systemPrompt += "\n\nCOMMODITY SPEC:\n\(specStr)"
      }
    }

    guard let url = URL(string: ClaudeConfig.baseURL) else { throw ClaudeServiceError.networkError("Invalid URL") }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(ClaudeConfig.apiKey, forHTTPHeaderField: "x-api-key")
    request.setValue(ClaudeConfig.apiVersion, forHTTPHeaderField: "anthropic-version")
    request.setValue("application/json", forHTTPHeaderField: "content-type")

    let body: [String: Any] = [
      "model": ClaudeConfig.model,
      "max_tokens": 2048,
      "system": systemPrompt,
      "messages": [["role": "user", "content": contentBlocks]]
    ]

    do { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
    catch { throw ClaudeServiceError.networkError("Serialize failed: \(error.localizedDescription)") }

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw ClaudeServiceError.networkError("Bad response") }
    guard (200...299).contains(http.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw ClaudeServiceError.apiError(http.statusCode, String(body.prefix(200)))
    }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let content = json["content"] as? [[String: Any]],
          let text = content.first?["text"] as? String else {
      throw ClaudeServiceError.decodingError("Could not extract text from batch response")
    }

    let jsonString = extractJSON(from: text)
    guard let jsonData = jsonString.data(using: .utf8) else { throw ClaudeServiceError.decodingError("UTF8 conversion failed") }
    return try JSONDecoder().decode(QCResult.self, from: jsonData)
  }

  private func extractJSON(from text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

    // If it starts with {, assume it's already JSON
    if trimmed.hasPrefix("{") {
      return trimmed
    }

    // Try to extract from ```json ... ``` code fences
    if let startRange = trimmed.range(of: "```json"),
       let endRange = trimmed.range(of: "```", range: startRange.upperBound..<trimmed.endIndex) {
      let jsonSlice = trimmed[startRange.upperBound..<endRange.lowerBound]
      return String(jsonSlice).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Try to extract from ``` ... ``` code fences
    if let startRange = trimmed.range(of: "```"),
       let endRange = trimmed.range(of: "```", range: startRange.upperBound..<trimmed.endIndex) {
      let jsonSlice = trimmed[startRange.upperBound..<endRange.lowerBound]
      return String(jsonSlice).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Try to find the first { and last }
    if let firstBrace = trimmed.firstIndex(of: "{"),
       let lastBrace = trimmed.lastIndex(of: "}") {
      return String(trimmed[firstBrace...lastBrace])
    }

    return trimmed
  }
}
