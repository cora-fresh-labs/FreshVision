@preconcurrency import AVFoundation
import SwiftUI

@MainActor
final class IPhoneCameraSource: NSObject, ObservableObject {
  private let pipeline = CameraPipeline()
  var session: AVCaptureSession { pipeline.session }
  @Published private(set) var permissionDenied = false
  @Published private(set) var isReady = false
  private var continuation: CheckedContinuation<CapturedFruitImage, Error>?

  func start() async {
    let granted: Bool
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: granted = true
    case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
    default: granted = false
    }
    guard granted else {
      permissionDenied = true
      return
    }
    permissionDenied = false
    configure()
  }

  func stop() {
    let pipeline = pipeline
    pipeline.queue.async {
      if pipeline.session.isRunning { pipeline.session.stopRunning() }
    }
  }

  func capture() async throws -> CapturedFruitImage {
    guard isReady else { throw CaptureError.notReady }
    guard continuation == nil else { throw CaptureError.captureInProgress }
    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
      settings.photoQualityPrioritization = .quality
      pipeline.output.capturePhoto(with: settings, delegate: self)
    }
  }

  private func configure() {
    guard !isReady else {
      let pipeline = pipeline
      pipeline.queue.async {
        if !pipeline.session.isRunning { pipeline.session.startRunning() }
      }
      return
    }
    let pipeline = pipeline
    pipeline.queue.async { [weak self] in
      guard let self else { return }
      pipeline.session.beginConfiguration()
      pipeline.session.sessionPreset = .photo
      defer { pipeline.session.commitConfiguration() }
      guard
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
        let input = try? AVCaptureDeviceInput(device: device),
        pipeline.session.canAddInput(input),
        pipeline.session.canAddOutput(pipeline.output)
      else {
        Task { @MainActor in self.permissionDenied = true }
        return
      }
      pipeline.session.addInput(input)
      pipeline.session.addOutput(pipeline.output)
      pipeline.output.maxPhotoQualityPrioritization = .quality
      pipeline.session.startRunning()
      Task { @MainActor in self.isReady = true }
    }
  }
}

private final class CameraPipeline: @unchecked Sendable {
  let session = AVCaptureSession()
  let output = AVCapturePhotoOutput()
  let queue = DispatchQueue(label: "com.cora.freshvision.camera")
}

extension IPhoneCameraSource: AVCapturePhotoCaptureDelegate {
  nonisolated func photoOutput(
    _ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?
  ) {
    Task { @MainActor in
      guard let continuation = self.continuation else { return }
      self.continuation = nil
      if let error {
        continuation.resume(throwing: error)
      } else if let data = photo.fileDataRepresentation() {
        continuation.resume(returning: .init(jpegData: data, source: .iPhone, capturedAt: Date()))
      } else {
        continuation.resume(throwing: CaptureError.noImageData)
      }
    }
  }
}

enum CaptureError: LocalizedError {
  case notReady, captureInProgress, noImageData, glassesNotConnected
  var errorDescription: String? {
    switch self {
    case .notReady: "The camera isn’t ready yet."
    case .captureInProgress: "One photo is already being taken."
    case .noImageData: "The photo didn’t save. Please try again."
    case .glassesNotConnected: "Connect your Meta glasses first."
    }
  }
}

struct CameraPreview: UIViewRepresentable {
  let session: AVCaptureSession
  func makeUIView(context: Context) -> PreviewView {
    let view = PreviewView()
    view.previewLayer.session = session
    view.previewLayer.videoGravity = .resizeAspectFill
    return view
  }
  func updateUIView(_ view: PreviewView, context: Context) { view.previewLayer.session = session }
}
final class PreviewView: UIView {
  override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
  var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
