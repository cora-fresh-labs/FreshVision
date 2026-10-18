import Foundation

enum FreshVisionAPIError: LocalizedError {
  case notConfigured, invalidResponse, timedOut
  case serverMessage(String)
  var errorDescription: String? {
    switch self {
    case .notConfigured: "FreshVision is not connected yet."
    case .invalidResponse: "I couldn’t read that result. Please try again."
    case .timedOut: "That took too long. Please try again."
    case .serverMessage(let text): text
    }
  }
}

struct ScanSyncPayload: Codable, Sendable {
  let id, installationId: UUID
  let capturedAt: Date
  let captureSource, deviceModel, analysisStatus: String
  let fruit, verdict, reason, issue: String?
  let confidence: Double?
  @MainActor init(scan: ScanRecord) {
    id = scan.id
    installationId = DeviceIdentity.installationID
    capturedAt = scan.capturedAt
    captureSource = scan.sourceRaw
    deviceModel = scan.deviceModel
    analysisStatus = scan.stateRaw
    fruit = scan.fruitRaw
    verdict = scan.verdictRaw
    reason = scan.reason
    issue = scan.issueRaw
    confidence = scan.confidence
  }
}

struct FeedbackSyncPayload: Codable, Sendable {
  let scanId, installationId: UUID
  let vote: String
  let votedAt: Date
  @MainActor init?(scan: ScanRecord) {
    guard let feedback = scan.feedback, let date = scan.feedbackAt else { return nil }
    scanId = scan.id
    installationId = DeviceIdentity.installationID
    vote = feedback.rawValue
    votedAt = date
  }
}

actor FreshVisionAPI {
  private let configuration: AppConfiguration
  private let session: URLSession
  private let auth: AuthSession
  private let tokenProvider: (@Sendable () async throws -> String)?
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(configuration: AppConfiguration = .live, session: URLSession? = nil,
       tokenProvider: (@Sendable () async throws -> String)? = nil) {
    self.configuration = configuration
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 15
    config.timeoutIntervalForResource = 20
    let transport = session ?? URLSession(configuration: config)
    self.session = transport
    self.tokenProvider = tokenProvider
    auth = AuthSession(configuration: configuration, session: transport)
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
  }

  func analyze(scanID: UUID, imageData: Data, source: CaptureSource) async throws
    -> FruitAnalysisResponse
  {
    struct Payload: Encodable {
      let scanId: UUID
      let imageBase64, captureSource: String
    }
    return try await post(
      "analyze-fruit",
      Payload(
        scanId: scanID, imageBase64: imageData.base64EncodedString(), captureSource: source.rawValue
      ))
  }

  func syncScan(_ scan: ScanSyncPayload, imageData: Data) async throws {
    struct Payload: Encodable {
      let scan: ScanSyncPayload
      let imageBase64: String
    }
    let _: EmptyResponse = try await post(
      "save-consumer-scan", Payload(scan: scan, imageBase64: imageData.base64EncodedString()))
  }

  func syncFeedback(_ payload: FeedbackSyncPayload) async throws {
    let _: EmptyResponse = try await post("save-consumer-feedback", payload)
  }

  func deleteScan(id: UUID) async throws {
    struct Payload: Encodable { let scanId: UUID }
    let _: EmptyResponse = try await post("delete-consumer-scan", Payload(scanId: id))
  }

  func verdictAudio(scanID: UUID) async throws -> Data {
    struct Payload: Encodable { let scanId: UUID }
    struct Audio: Decodable {
      let voiceId, contentType, audioBase64: String
    }
    let audio: Audio = try await post("speak-verdict", Payload(scanId: scanID))
    guard audio.voiceId == "56bWURjYFHyYyVf490Dp", audio.contentType == "audio/mpeg",
      audio.audioBase64.count <= 1_400_000,
      let data = Data(base64Encoded: audio.audioBase64), !data.isEmpty
    else { throw FreshVisionAPIError.invalidResponse }
    return data
  }

  private func post<P: Encodable, R: Decodable>(_ function: String, _ payload: P) async throws -> R
  {
    guard configuration.isConfigured, let url = configuration.functionURL(function) else {
      throw FreshVisionAPIError.notConfigured
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = try encoder.encode(payload)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(configuration.supabaseAnonKey, forHTTPHeaderField: "apikey")
    let token: String
    if let tokenProvider { token = try await tokenProvider() }
    else { token = try await auth.accessToken() }
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    do {
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        throw FreshVisionAPIError.invalidResponse
      }
      guard (200..<300).contains(http.statusCode) else {
        throw FreshVisionAPIError.serverMessage(
          (try? decoder.decode(APIErrorBody.self, from: data).error)
            ?? "FreshVision couldn’t finish that scan.")
      }
      guard let value = try? decoder.decode(R.self, from: data.isEmpty ? Data("{}".utf8) : data) else {
        throw FreshVisionAPIError.invalidResponse
      }
      return value
    } catch let error as URLError where error.code == .timedOut {
      throw FreshVisionAPIError.timedOut
    } catch let error as URLError where error.code == .notConnectedToInternet
      || error.code == .networkConnectionLost || error.code == .cannotConnectToHost {
      throw FreshVisionAPIError.serverMessage("You’re offline. Your photo is saved. Try again when connected.")
    }
  }
}

private struct EmptyResponse: Decodable {}
private struct APIErrorBody: Decodable { let error: String }
