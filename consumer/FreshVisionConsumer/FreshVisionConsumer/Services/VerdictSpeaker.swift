import AVFoundation
import Combine

@MainActor
final class VerdictSpeaker: NSObject, ObservableObject, AVAudioPlayerDelegate {
  @Published private(set) var isLoading = false
  @Published private(set) var isPlaying = false
  @Published private(set) var message: String?
  private var player: AVAudioPlayer?
  private var task: Task<Void, Never>?
  private var cache: [UUID: Data] = [:]

  func speak(scanID: UUID, api: FreshVisionAPI) {
    stop()
    isLoading = true
    task = Task { [weak self] in
      guard let self else { return }
      do {
        let data: Data
        if let cached = cache[scanID] { data = cached }
        else { data = try await api.verdictAudio(scanID: scanID) }
        try Task.checkCancellation()
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetoothA2DP])
        try audio.setActive(true)
        let player = try AVAudioPlayer(data: data)
        player.delegate = self
        guard player.prepareToPlay(), player.play() else { throw FreshVisionAPIError.invalidResponse }
        self.player = player
        if cache.count >= 10 { cache.removeAll() }
        cache[scanID] = data
        isLoading = false
        isPlaying = true
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled else { return }
        stop()
        message = "Emma’s voice is unavailable. Your result is still here."
      }
    }
  }

  func stop() {
    task?.cancel()
    task = nil
    player?.stop()
    player = nil
    isLoading = false
    isPlaying = false
    message = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  func invalidate(_ id: UUID) { cache[id] = nil }

  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor [weak self] in self?.stop() }
  }

  nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    Task { @MainActor [weak self] in
      self?.stop()
      self?.message = "Emma’s voice is unavailable. Your result is still here."
    }
  }
}
