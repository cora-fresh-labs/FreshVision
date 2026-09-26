import AVFoundation

@MainActor
final class VerdictSpeaker {
  private let synthesizer = AVSpeechSynthesizer()

  func speak(verdict: FruitVerdict, reason: String) {
    let audio = AVAudioSession.sharedInstance()
    try? audio.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetoothA2DP])
    try? audio.setActive(true)
    let utterance = AVSpeechUtterance(string: "\(verdict.rawValue). \(reason)")
    utterance.rate = 0.5
    synthesizer.stopSpeaking(at: .immediate)
    synthesizer.speak(utterance)
  }
}
