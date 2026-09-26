import AVFoundation

@MainActor
final class VerdictSpeaker: NSObject, AVSpeechSynthesizerDelegate {
  private let synthesizer = AVSpeechSynthesizer()

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  func speak(verdict: FruitVerdict, reason: String) {
    let audio = AVAudioSession.sharedInstance()
    try? audio.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetoothA2DP])
    try? audio.setActive(true)
    let utterance = AVSpeechUtterance(string: "\(verdict.rawValue). \(reason)")
    utterance.rate = 0.5
    synthesizer.stopSpeaking(at: .immediate)
    synthesizer.speak(utterance)
  }

  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    Task { @MainActor in self.deactivateAudio() }
  }

  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    Task { @MainActor in self.deactivateAudio() }
  }

  private func deactivateAudio() {
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}
