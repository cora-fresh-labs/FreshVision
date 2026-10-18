import XCTest
import SwiftData
import UIKit
@testable import FreshVisionConsumer

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let (status, data) = try Self.handler!(request)
      let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                     headerFields: ["Content-Type": "application/json"])!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}

private struct MemoryCredentials: AuthCredentialStorage {
  let value: AuthCredentials?
  func load() -> AuthCredentials? { value }
  func save(_ credentials: AuthCredentials) throws {}
}

final class BetaFlowTests: XCTestCase {
  private func session() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FixtureProtocol.self]
    return URLSession(configuration: config)
  }
  private func api(configured: Bool = true) -> FreshVisionAPI {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FixtureProtocol.self]
    return FreshVisionAPI(configuration: .init(
      supabaseURL: URL(string: "https://fixture.invalid"), supabaseAnonKey: configured ? "public-fixture" : ""),
      session: URLSession(configuration: config), tokenProvider: { "fixture-user-jwt" })
  }

  func testMissingConfigurationFailsBeforeAnyNetworkCall() async {
    FixtureProtocol.handler = { _ in XCTFail("No request should leave an unconfigured app"); return (500, Data()) }
    do { _ = try await api(configured: false).verdictAudio(scanID: UUID()); XCTFail("Expected configuration error") }
    catch { XCTAssertEqual(error.localizedDescription, "FreshVision is not connected yet.") }
  }

  func testConfigurationRejectsProviderAndServiceCredentials() {
    let url = URL(string: "https://fixture.invalid")!
    XCTAssertFalse(AppConfiguration(supabaseURL: url, supabaseAnonKey: "sb_secret_fixture").isConfigured)
    XCTAssertFalse(AppConfiguration(supabaseURL: URL(string: "http://fixture.invalid"), supabaseAnonKey: "sb_publishable_fixture").isConfigured)
    let role = Data(#"{"role":"service_role"}"#.utf8).base64EncodedString()
    XCTAssertFalse(AppConfiguration(supabaseURL: url, supabaseAnonKey: "header.\(role).signature").isConfigured)
    XCTAssertTrue(AppConfiguration(supabaseURL: url, supabaseAnonKey: "sb_publishable_fixture").isConfigured)
  }

  func testOfflineRefreshKeepsTheSameOwnerAndNeverSignsUpAgain() async {
    var refreshes = 0
    FixtureProtocol.handler = { request in
      XCTAssertEqual(request.url?.lastPathComponent, "token")
      refreshes += 1
      throw URLError(.notConnectedToInternet)
    }
    let auth = AuthSession(configuration: .init(supabaseURL: URL(string: "https://fixture.invalid"),
                                               supabaseAnonKey: "public-fixture"), session: session(),
                           store: MemoryCredentials(value: .init(accessToken: "expired-fixture",
                             refreshToken: "same-owner-fixture", expiresAt: .distantPast)))
    for _ in 0..<2 {
      do { _ = try await auth.accessToken(); XCTFail("Expected offline error") } catch {}
    }
    XCTAssertEqual(refreshes, 2)
  }

  func testConcurrentSessionRequestsShareOneAnonymousIdentity() async throws {
    var signups = 0
    FixtureProtocol.handler = { request in
      XCTAssertEqual(request.url?.lastPathComponent, "signup")
      signups += 1
      return (200, Data(#"{"access_token":"same-user","refresh_token":"fixture-refresh","expires_in":3600}"#.utf8))
    }
    let auth = AuthSession(configuration: .init(supabaseURL: URL(string: "https://fixture.invalid"),
                                               supabaseAnonKey: "public-fixture"), session: session(),
                           store: MemoryCredentials(value: nil))
    async let first = auth.accessToken()
    async let second = auth.accessToken()
    let tokens = try await [first, second]
    XCTAssertEqual(tokens, ["same-user", "same-user"])
    XCTAssertEqual(signups, 1)
  }

  func testOfflineAndTimeoutAreActionable() async {
    for (code, message) in [(URLError.Code.notConnectedToInternet, "You’re offline. Your photo is saved. Try again when connected."),
                            (.timedOut, "That took too long. Please try again.")] {
      FixtureProtocol.handler = { _ in throw URLError(code) }
      do { _ = try await api().verdictAudio(scanID: UUID()); XCTFail("Expected transport failure") }
      catch { XCTAssertEqual(error.localizedDescription, message) }
    }
  }

  func testSpeechUsesPrivateBackendAndExactEmmaVoice() async throws {
    FixtureProtocol.handler = { request in
      XCTAssertEqual(request.url?.host, "fixture.invalid")
      XCTAssertEqual(request.url?.lastPathComponent, "speak-verdict")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-user-jwt")
      XCTAssertNil(request.value(forHTTPHeaderField: "xi-api-key"))
      return (200, Data(#"{"voiceId":"56bWURjYFHyYyVf490Dp","contentType":"audio/mpeg","audioBase64":"SUQz"}"#.utf8))
    }
    let audio = try await api().verdictAudio(scanID: UUID())
    XCTAssertEqual(audio, Data("ID3".utf8))
  }

  func testWrongVoiceAndMalformedAudioAreRejected() async {
    for body in [#"{"voiceId":"someone-else","contentType":"audio/mpeg","audioBase64":"SUQz"}"#,
                 #"{"voiceId":"56bWURjYFHyYyVf490Dp","contentType":"audio/mpeg","audioBase64":"%%%"}"#,
                 #"{"voiceId":"56bWURjYFHyYyVf490Dp","contentType":"audio/mpeg","audioBase64":""}"#] {
      FixtureProtocol.handler = { _ in (200, Data(body.utf8)) }
      do { _ = try await api().verdictAudio(scanID: UUID()); XCTFail("Expected invalid audio failure") }
      catch { XCTAssertEqual(error.localizedDescription, "I couldn’t read that result. Please try again.") }
    }
  }

  @MainActor
  func testBackendAudioPlaysAndStopReleasesPlayback() async throws {
    let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "playback-tone", withExtension: "mp3"))
    let data = try Data(contentsOf: url)
    let body = try JSONSerialization.data(withJSONObject: [
      "voiceId": "56bWURjYFHyYyVf490Dp", "contentType": "audio/mpeg", "audioBase64": data.base64EncodedString(),
    ])
    FixtureProtocol.handler = { _ in (200, body) }
    let speaker = VerdictSpeaker()
    speaker.speak(scanID: UUID(), api: api())
    for _ in 0..<100 where !speaker.isPlaying && speaker.message == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertTrue(speaker.isPlaying, "Synthetic tone fixture should reach the actual AVAudioPlayer")
    XCTAssertNil(speaker.message)
    speaker.stop()
    XCTAssertFalse(speaker.isPlaying)
    XCTAssertFalse(speaker.isLoading)
  }

  @MainActor
  func testPhotoFailurePersistsHistoryAndRequiresExplicitAnalysisRetry() async throws {
    var analyses = 0
    FixtureProtocol.handler = { request in
      if request.url?.lastPathComponent == "analyze-fruit" { analyses += 1; throw URLError(.notConnectedToInternet) }
      throw URLError(.notConnectedToInternet)
    }
    let container = try ModelContainer(for: ScanRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let controller = ScanController(api: api())
    controller.attach(container.mainContext)
    let jpeg = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
      UIColor.yellow.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
    }.jpegData(compressionQuality: 0.8)!
    await controller.importPhoto(jpeg)
    let scans = try container.mainContext.fetch(FetchDescriptor<ScanRecord>())
    XCTAssertEqual(scans.count, 1)
    let saved = try XCTUnwrap(scans.first)
    XCTAssertEqual(saved.state, .needsRetry)
    XCTAssertNotNil(controller.image(for: saved))
    XCTAssertEqual(controller.phase, .result)
    await controller.syncPending()
    XCTAssertEqual(analyses, 1, "Background sync must not automatically spend on another analysis")
    await controller.retry(saved)
    XCTAssertEqual(analyses, 2)
    XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ScanRecord>()), 1)
    try ImageStore().delete(saved.imageFilename)
  }

  @MainActor
  func testSuccessfulPhotoResultSurvivesSpeechFailureAndCanReopenFromHistory() async throws {
    FixtureProtocol.handler = { request in
      if request.url?.lastPathComponent == "analyze-fruit" {
        return (200, Data(#"{"supported":true,"fruit":"banana","verdict":"Buy \u2014 ready now","reason":"The peel is yellow.","issue":null,"confidence":0.9}"#.utf8))
      }
      if request.url?.lastPathComponent == "speak-verdict" {
        return (503, Data(#"{"error":"Emma’s voice is unavailable. Your result is still here."}"#.utf8))
      }
      return (200, Data("{}".utf8))
    }
    let container = try ModelContainer(for: ScanRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let controller = ScanController(api: api())
    controller.attach(container.mainContext)
    let jpeg = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in }.jpegData(compressionQuality: 0.8)!
    await controller.importPhoto(jpeg)
    let scan = try XCTUnwrap(controller.activeScan)
    XCTAssertEqual(scan.state, .complete)
    XCTAssertEqual(scan.verdict, .readyNow)
    XCTAssertNotNil(scan.scanSyncedAt)
    controller.newScan()
    controller.show(scan)
    XCTAssertEqual(controller.activeScan?.id, scan.id)
    XCTAssertEqual(controller.phase, .result)
    try ImageStore().delete(scan.imageFilename)
    controller.speaker.stop()
  }
}
