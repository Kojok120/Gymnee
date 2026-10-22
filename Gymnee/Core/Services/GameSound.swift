import AVFoundation
import Foundation

/// ゲームの効果音と BGM（issue #155）。音源は `scripts/audio/make_game_sounds.py` で合成した 8bit 風の音。
///
/// レスト終了のチャイム（`RestChime`）とは役割が違う。チャイムは「気づかせる」ための音なので
/// サイレントスイッチを越えて鳴らすが、効果音と BGM は**演出**なので、サイレントなら鳴らさず
/// （`.ambient`）、聞いている音楽も止めない（`.mixWithOthers`）。BGM は音楽を聞いているときは流さない。
@MainActor
enum GameSound {

    enum Effect: String, CaseIterable {
        case hit = "sfx_hit"
        case critical = "sfx_critical"
        case finish = "sfx_finish"
        case levelUp = "sfx_levelup"
        case evolve = "sfx_evolve"
        case chest = "sfx_chest"
        case learn = "sfx_learn"
    }

    /// 設定のトグル。未設定は ON。
    static let effectsKey = "gymnee.gameSoundEnabled"
    static let musicKey = "gymnee.bossMusicEnabled"

    static var effectsEnabled: Bool { UserDefaults.standard.object(forKey: effectsKey) as? Bool ?? true }
    static var musicEnabled: Bool { UserDefaults.standard.object(forKey: musicKey) as? Bool ?? true }

    private static var players: [Effect: AVAudioPlayer] = [:]
    private static var music: AVAudioPlayer?

    /// 効果音を鳴らす。連打されたら頭から鳴らし直す（重ねると音が割れる）。
    static func play(_ effect: Effect) {
        guard effectsEnabled, prepareSession() else { return }
        guard let player = player(for: effect) else { return }
        player.currentTime = 0
        player.play()
    }

    /// ボス部屋の BGM を流す。音楽を聞いているとき・設定で切っているときは流さない。
    static func startBossMusic() {
        guard musicEnabled, music?.isPlaying != true else { return }
        guard !AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint, prepareSession() else { return }
        guard let url = Bundle.main.url(forResource: "bgm_boss", withExtension: "caf"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = -1
        player.volume = 0.45
        player.play()
        music = player
    }

    static func stopBossMusic() {
        music?.stop()
        music = nil
    }

    private static func player(for effect: Effect) -> AVAudioPlayer? {
        if let cached = players[effect] { return cached }
        guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.volume = 0.8
        player.prepareToPlay()
        players[effect] = player
        return player
    }

    /// 演出用のセッションにする。レストのチャイムが `.playback` に切り替えていても、鳴らす直前に戻す。
    private static func prepareSession() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            if session.category != .ambient {
                try session.setCategory(.ambient, options: [.mixWithOthers])
            }
            try session.setActive(true)
            return true
        } catch {
            return false
        }
    }
}
