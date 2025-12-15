import Foundation
import AVFoundation

final class SoundManager {
    static let shared = SoundManager()
    
    private var correctPlayer: AVAudioPlayer?
    private var wrongPlayer: AVAudioPlayer?
    
    private init() {
        correctPlayer = Self.makePlayer(resource: "correct", ext: "mp3")
        wrongPlayer = Self.makePlayer(resource: "error", ext: "mp3")
        correctPlayer?.prepareToPlay()
        wrongPlayer?.prepareToPlay()
    }
    
    private static func makePlayer(resource: String, ext: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            print("⚠️ Sound resource not found: \(resource).\(ext)")
            return nil
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 1.0
            return player
        } catch {
            print("⚠️ Audio init error for \(resource).\(ext): \(error)")
            return nil
        }
    }
    
    func playCorrect() {
        play(player: correctPlayer)
    }
    
    func playWrong() {
        play(player: wrongPlayer)
    }
    
    private func play(player: AVAudioPlayer?) {
        guard let player else { return }
        if player.isPlaying {
            player.stop()
        }
        player.currentTime = 0
        player.play()
    }
}




