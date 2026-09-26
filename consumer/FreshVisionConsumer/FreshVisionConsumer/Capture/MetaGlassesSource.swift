import MWDATCamera
import MWDATCore
import MWDATInputs
import UIKit

@MainActor
final class MetaGlassesSource: ObservableObject {
  @Published private(set) var registrationState: RegistrationState
  @Published private(set) var devices: [DeviceIdentifier]
  @Published private(set) var sessionState: DeviceSessionState = .idle
  @Published private(set) var streamState: StreamState = .stopped
  @Published private(set) var previewImage: UIImage?
  @Published private(set) var captureButtonRequest = UUID()
  @Published var message: String?

  private let wearables: WearablesInterface?
  private let selector: AutoDeviceSelector?
  private var deviceSession: DeviceSession?
  private var camera: MWDATCamera.Camera?
  private var inputs: Inputs?
  private let sessionTokens = ListenerTokenBag()
  private let streamTokens = ListenerTokenBag()
  private var registrationTask: Task<Void, Never>?
  private var devicesTask: Task<Void, Never>?
  private var inputsTask: Task<Void, Never>?
  private var photoContinuation: CheckedContinuation<CapturedFruitImage, Error>?

  init(wearables: WearablesInterface? = MetaRuntime.interface) {
    self.wearables = wearables
    selector = wearables.map { AutoDeviceSelector(wearables: $0) }
    registrationState = wearables?.registrationState ?? .unavailable
    devices = wearables?.devices ?? []
    message = MetaRuntime.setupMessage
    if let wearables {
      registrationTask = Task { [weak self] in
        for await state in wearables.registrationStateStream() { self?.registrationState = state }
      }
      devicesTask = Task { [weak self] in
        for await values in wearables.devicesStream() { self?.devices = values }
      }
    }
  }
  deinit {
    registrationTask?.cancel()
    devicesTask?.cancel()
  }
  var isRegistered: Bool { registrationState == .registered }
  var isStreaming: Bool { streamState == .streaming }

  func register() async {
    guard let wearables else {
      message = MetaRuntime.setupMessage ?? "Meta glasses are not configured yet."
      return
    }
    do { try await wearables.startRegistration() } catch {
      message = "I couldn’t connect to Meta AI. Please try again."
    }
  }
  func handle(url: URL) async {
    guard
      URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: {
        $0.name == "metaWearablesAction"
      }) == true
    else { return }
    guard let wearables else {
      message = MetaRuntime.setupMessage ?? "Meta glasses are not configured yet."
      return
    }
    do { _ = try await wearables.handleUrl(url) } catch {
      message = "The glasses connection didn’t finish. Please try again."
    }
  }
  func connectAndPreview() async {
    guard let wearables, let selector else {
      message = MetaRuntime.setupMessage ?? "Meta glasses are not configured yet."
      return
    }
    guard isRegistered, !devices.isEmpty else {
      message = "Connect your Meta glasses first."
      return
    }
    do {
      if deviceSession == nil {
        let session = try wearables.createSession(deviceSelector: selector)
        deviceSession = session
        session.statePublisher.listen { [weak self] state in
          Task { @MainActor in self?.sessionState = state }
        }.store(in: sessionTokens)
        try session.start()
        for await state in session.stateStream() {
          if state == .started { break }
          if state == .stopped { throw CaptureError.glassesNotConnected }
        }
      }
      try startInputs()
      try await startPreview()
    } catch {
      message = "I couldn’t start the glasses camera. Please try again."
      stop()
    }
  }
  func capture() async throws -> CapturedFruitImage {
    guard isStreaming, photoContinuation == nil else { throw CaptureError.glassesNotConnected }
    return try await withCheckedThrowingContinuation { continuation in
      photoContinuation = continuation
      if camera?.stream.capturePhoto(format: .jpeg) != true {
        photoContinuation = nil
        continuation.resume(throwing: CaptureError.noImageData)
      }
    }
  }
  func stop() {
    camera?.stop()
    try? deviceSession?.removeInputs()
    deviceSession?.stop()
    streamTokens.clear()
    sessionTokens.clear()
    inputsTask?.cancel()
    inputsTask = nil
    inputs = nil
    camera = nil
    deviceSession = nil
    previewImage = nil
    streamState = .stopped
    sessionState = .idle
  }
  private func startInputs() throws {
    guard let session = deviceSession, inputs == nil else { return }
    let inputs = try session.addInputs(
      configuration: InputsConfiguration(sources: [.captureButton], consumeBack: false))
    self.inputs = inputs
    inputsTask = Task { [weak self] in
      guard let inputs else { return }
      for await event in inputs.events {
        guard case .capture(.shortPress, _, _) = event else { continue }
        await MainActor.run { self?.captureButtonRequest = UUID() }
      }
    }
  }
  private func startPreview() async throws {
    guard let wearables else { throw CaptureError.glassesNotConnected }
    guard let session = deviceSession, session.state == .started, camera == nil else { return }
    if try await wearables.checkPermissionStatus(.camera) != .granted {
      guard try await wearables.requestPermission(.camera) == .granted else {
        throw CaptureError.glassesNotConnected
      }
    }
    let config = StreamConfiguration(videoCodec: .raw, resolution: .medium, frameRate: 15)
    guard let camera = try session.addCamera(config: config) else {
      throw CaptureError.glassesNotConnected
    }
    self.camera = camera
    camera.stream.statePublisher.listen { [weak self] state in
      Task { @MainActor in self?.streamState = state }
    }.store(in: streamTokens)
    camera.stream.videoFramePublisher.listen { [weak self] frame in
      guard let image = frame.makeUIImage() else { return }
      Task { @MainActor in self?.previewImage = image }
    }.store(in: streamTokens)
    camera.stream.photoDataPublisher.listen { [weak self] photo in
      Task { @MainActor in self?.finish(photo.data) }
    }.store(in: streamTokens)
    camera.stream.start()
  }
  private func finish(_ data: Data) {
    guard let continuation = photoContinuation else { return }
    photoContinuation = nil
    continuation.resume(returning: .init(jpegData: data, source: .metaGlasses, capturedAt: Date()))
  }
}
