/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamSessionViewModel.swift
//
// Core view model demonstrating video streaming from Meta wearable devices using the DAT SDK.
// This class showcases the key streaming patterns: device selection, session management,
// video frame handling, photo capture, and error handling.
//

import AVFoundation
import MediaPlayer
import MWDATCamera
import MWDATCore
import SwiftUI
import UIKit

enum StreamingStatus {
  case streaming
  case waiting
  case stopped
}

enum StreamingMode {
  case glasses
  case iPhone
}

struct CapturedPhotoQueueItem {
  let id: UUID
  let image: UIImage
}

@MainActor
class StreamSessionViewModel: ObservableObject {
  @Published var currentVideoFrame: UIImage?
  @Published var hasReceivedFirstFrame: Bool = false
  @Published var streamingStatus: StreamingStatus = .stopped
  @Published var showError: Bool = false
  @Published var errorMessage: String = ""
  @Published var hasActiveDevice: Bool = false
  @Published var streamingMode: StreamingMode = .glasses

  var isStreaming: Bool {
    streamingStatus != .stopped
  }

  // Photo capture properties
  @Published var capturedPhoto: UIImage?
  @Published var capturedPhotos: [CapturedPhotoQueueItem] = []
  @Published var showPhotoPreview: Bool = false

  // Gemini Live integration (stub — kept for compatibility)
  var geminiSessionVM: GeminiSessionViewModel?

  // FreshVision (Claude) integration
  var freshVisionVM: FreshVisionViewModel?

  // The core DAT SDK StreamSession - handles all streaming operations
  private var streamSession: StreamSession
  // Listener tokens are used to manage DAT SDK event subscriptions
  private var stateListenerToken: AnyListenerToken?
  private var videoFrameListenerToken: AnyListenerToken?
  private var errorListenerToken: AnyListenerToken?
  private var photoDataListenerToken: AnyListenerToken?
  private let wearables: WearablesInterface
  private let deviceSelector: AutoDeviceSelector
  private var deviceMonitorTask: Task<Void, Never>?
  private var iPhoneCameraManager: IPhoneCameraManager?

  // Volume button capture: press volume up/down to snap a photo hands-free
  private var volumeObserver: NSKeyValueObservation?
  private var lastVolumeCapture: Date = .distantPast

  init(wearables: WearablesInterface) {
    self.wearables = wearables
    // Let the SDK auto-select from available devices
    self.deviceSelector = AutoDeviceSelector(wearables: wearables)
    let config = StreamSessionConfig(
      videoCodec: VideoCodec.raw,
      resolution: StreamingResolution.high,
      frameRate: 24)
    streamSession = StreamSession(streamSessionConfig: config, deviceSelector: deviceSelector)

    // Monitor device availability
    deviceMonitorTask = Task { @MainActor in
      for await device in deviceSelector.activeDeviceStream() {
        self.hasActiveDevice = device != nil
      }
    }

    // Subscribe to session state changes using the DAT SDK listener pattern
    // State changes tell us when streaming starts, stops, or encounters issues
    stateListenerToken = streamSession.statePublisher.listen { [weak self] state in
      Task { @MainActor [weak self] in
        self?.updateStatusFromState(state)
      }
    }

    // Subscribe to video frames from the device camera
    // Each VideoFrame contains the raw camera data that we convert to UIImage
    videoFrameListenerToken = streamSession.videoFramePublisher.listen { [weak self] videoFrame in
      Task { @MainActor [weak self] in
        guard let self else { return }

        if let image = videoFrame.makeUIImage() {
          self.currentVideoFrame = image
          if !self.hasReceivedFirstFrame {
            self.hasReceivedFirstFrame = true
          }
          // Forward latest frame to FreshVision for tap-to-inspect
          self.freshVisionVM?.updateLatestFrame(image)
        }
      }
    }

    // Subscribe to streaming errors
    // Errors include device disconnection, streaming failures, etc.
    errorListenerToken = streamSession.errorPublisher.listen { [weak self] error in
      Task { @MainActor [weak self] in
        guard let self else { return }
        let newErrorMessage = formatStreamingError(error)
        if newErrorMessage != self.errorMessage {
          showError(newErrorMessage)
        }
      }
    }

    updateStatusFromState(streamSession.state)

    // Subscribe to photo capture events
    // PhotoData contains the captured image in the requested format (JPEG/HEIC)
    photoDataListenerToken = streamSession.photoDataPublisher.listen { [weak self] photoData in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if let uiImage = UIImage(data: photoData.data) {
          let optimized = self.optimizeForQueue(uiImage)
          self.capturedPhoto = optimized
          let item = CapturedPhotoQueueItem(id: UUID(), image: optimized)
          self.capturedPhotos.append(item)
          if self.capturedPhotos.count > 20 {
            self.capturedPhotos.removeFirst(self.capturedPhotos.count - 20)
          }
          self.freshVisionVM?.registerCapturedPhoto(optimized, id: item.id)
          self.freshVisionVM?.addBatchPhoto(optimized)
          // Keep the flow uninterrupted during inspections (no modal preview spam)
          self.showPhotoPreview = false
        }
      }
    }
  }

  func handleStartStreaming() async {
    let permission = Permission.camera
    do {
      let status = try await wearables.checkPermissionStatus(permission)
      if status == .granted {
        await startSession()
        return
      }
      let requestStatus = try await wearables.requestPermission(permission)
      if requestStatus == .granted {
        await startSession()
        return
      }
      showError("Permission denied")
    } catch {
      showError("Permission error: \(error.description)")
    }
  }

  func startSession() async {
    await streamSession.start()
    startVolumeButtonCapture()
  }

  // MARK: - Volume Button Capture (hands-free photo trigger)

  /// Listen for volume button presses to trigger photo capture.
  /// This lets the user snap photos while wearing glasses without touching the screen.
  /// Uses AVAudioSession outputVolume KVO — works even when phone is in pocket.
  private func startVolumeButtonCapture() {
    // Set up audio session to observe volume changes
    let audioSession = AVAudioSession.sharedInstance()
    do {
      try audioSession.setActive(true)
    } catch {
      NSLog("[Stream] Volume button capture setup failed: %@", error.localizedDescription)
      return
    }

    // Hide the system volume HUD by adding an invisible MPVolumeView
    // (the parent view should add this — but the KVO approach still works)

    volumeObserver = audioSession.observe(\.outputVolume, options: [.new, .old]) { [weak self] _, change in
      Task { @MainActor [weak self] in
        guard let self else { return }
        guard self.streamingStatus == .streaming else { return }

        // Debounce: ignore presses within 0.5 seconds of each other
        let now = Date()
        guard now.timeIntervalSince(self.lastVolumeCapture) > 0.5 else { return }

        // Only trigger if volume actually changed (not initial observation)
        guard let oldVal = change.oldValue, let newVal = change.newValue, oldVal != newVal else { return }

        self.lastVolumeCapture = now
        self.capturePhoto()
        NSLog("[Stream] Volume button photo captured (vol: %.2f → %.2f)", oldVal, newVal)
      }
    }

    NSLog("[Stream] Volume button capture enabled — press volume up/down to snap photos")
  }

  private func stopVolumeButtonCapture() {
    volumeObserver?.invalidate()
    volumeObserver = nil
  }

  private func showError(_ message: String) {
    errorMessage = message
    showError = true
  }

  func stopSession() async {
    if streamingMode == .iPhone {
      stopIPhoneSession()
      return
    }
    stopVolumeButtonCapture()
    await streamSession.stop()
  }

  // MARK: - iPhone Camera Mode

  func handleStartIPhone() async {
    let granted = await IPhoneCameraManager.requestPermission()
    if granted {
      startIPhoneSession()
    } else {
      showError("Camera permission denied. Please grant access in Settings.")
    }
  }

  private func startIPhoneSession() {
    streamingMode = .iPhone
    let camera = IPhoneCameraManager()
    camera.onFrameCaptured = { [weak self] image in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.currentVideoFrame = image
        if !self.hasReceivedFirstFrame {
          self.hasReceivedFirstFrame = true
        }
        // Forward latest frame to FreshVision for tap-to-inspect
        self.freshVisionVM?.updateLatestFrame(image)
      }
    }
    camera.start()
    iPhoneCameraManager = camera
    streamingStatus = .streaming
    startVolumeButtonCapture()
    NSLog("[Stream] iPhone camera mode started")
  }

  private func stopIPhoneSession() {
    iPhoneCameraManager?.stop()
    iPhoneCameraManager = nil
    currentVideoFrame = nil
    hasReceivedFirstFrame = false
    streamingStatus = .stopped
    streamingMode = .glasses
    stopVolumeButtonCapture()
    NSLog("[Stream] iPhone camera mode stopped")
  }

  func dismissError() {
    showError = false
    errorMessage = ""
  }

  func capturePhoto() {
    if streamingMode == .iPhone {
      guard let frame = currentVideoFrame else {
        showError("No camera frame available to capture.")
        return
      }
      let optimized = optimizeForQueue(frame)
      capturedPhoto = optimized
      let item = CapturedPhotoQueueItem(id: UUID(), image: optimized)
      capturedPhotos.append(item)
      if capturedPhotos.count > 20 {
        capturedPhotos.removeFirst(capturedPhotos.count - 20)
      }
      freshVisionVM?.registerCapturedPhoto(optimized, id: item.id)
      freshVisionVM?.addBatchPhoto(optimized)
      showPhotoPreview = false
      return
    }

    streamSession.capturePhoto(format: .jpeg)
  }

  private func optimizeForQueue(_ image: UIImage) -> UIImage {
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

  func dequeueCapturedPhoto() -> CapturedPhotoQueueItem? {
    guard !capturedPhotos.isEmpty else { return nil }
    return capturedPhotos.removeFirst()
  }

  func dismissPhotoPreview() {
    showPhotoPreview = false
    capturedPhoto = nil
  }

  func clearCapturedPhotos() {
    capturedPhotos.removeAll()
    capturedPhoto = nil
    showPhotoPreview = false
  }

  private func updateStatusFromState(_ state: StreamSessionState) {
    switch state {
    case .stopped:
      currentVideoFrame = nil
      streamingStatus = .stopped
    case .waitingForDevice, .starting, .stopping, .paused:
      streamingStatus = .waiting
    case .streaming:
      streamingStatus = .streaming
    }
  }

  private func formatStreamingError(_ error: StreamSessionError) -> String {
    switch error {
    case .internalError:
      return "An internal error occurred. Please try again."
    case .deviceNotFound:
      return "Device not found. Please ensure your device is connected."
    case .deviceNotConnected:
      return "Device not connected. Please check your connection and try again."
    case .timeout:
      return "The operation timed out. Please try again."
    case .videoStreamingError:
      return "Video streaming failed. Please try again."
    case .audioStreamingError:
      return "Audio streaming failed. Please try again."
    case .permissionDenied:
      return "Camera permission denied. Please grant permission in Settings."
    case .hingesClosed:
      return "The hinges on the glasses were closed. Please open the hinges and try again."
    @unknown default:
      return "An unknown streaming error occurred."
    }
  }
}
