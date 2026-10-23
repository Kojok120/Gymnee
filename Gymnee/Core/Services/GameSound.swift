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
        /// コマンドを選んだ（issue #161）。
        case select = "sfx_select"
    }

    /// BGM の曲。
    enum Music: String {
        /// 部屋（育成タブ）。ずっと居る場所なのでボス部屋より小さく流す。
        case room = "bgm_room"
        /// ボス部屋。
        case boss = "bgm_boss"

        var volume: Float {
            switch self {
            case .room: return 0.4
            case .boss: return 0.45
            }
        }
    }

    /// 設定のトグル。未設定は ON。
    static let effectsKey = "gymnee.gameSoundEnabled"
    /// BGM のトグル。キーの名前はボス部屋にしか BGM が無かった頃のまま（切った人の設定を引き継ぐ）。
    static let musicKey = "gymnee.bossMusicEnabled"

    static var effectsEnabled: Bool { UserDefaults.standard.object(forKey: effectsKey) as? Bool ?? true }
    static var musicEnabled: Bool { UserDefaults.standard.object(forKey: musicKey) as? Bool ?? true }

    private static var players: [Effect: AVAudioPlayer] = [:]
    /// いま見えている画面が流したい曲。流せなかったときも覚えておき、アプリに戻ったときに流し直す。
    private static var wanted: Music?
    private static var music: AVAudioPlayer?
    private static var playing: Music?

    /// 効果音を鳴らす。連打されたら頭から鳴らし直す（重ねると音が割れる）。
    static func play(_ effect: Effect) {
        guard effectsEnabled, prepareSession() else { return }
        guard let player = player(for: effect) else { return }
        player.currentTime = 0
        player.play()
    }

    /// 画面に入ったら呼ぶ。同じ曲が流れていれば頭から鳴らし直さない。
    static func startMusic(_ track: Music) {
        wanted = track
        playWanted()
    }

    /// 画面を出たら呼ぶ。その曲を流しているときだけ止める
    /// （部屋⇄ボス部屋の切り替えで、行き先が先に次の曲を始めていたらそれは止めない）。
    static func stopMusic(_ track: Music) {
        guard wanted == track else { return }
        wanted = nil
        stopPlayer()
    }

    /// アプリに戻ったときに呼ぶ。`.ambient` は裏に回ると OS に止められ、戻っても自分では鳴り直さない。
    static func resumeMusic() {
        playWanted()
    }

    /// 見えている画面の曲を流す。音楽を聞いているとき・設定で切っているときは流さない。
    private static func playWanted() {
        guard let track = wanted, musicEnabled,
              !AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint else {
            stopPlayer()
            return
        }
        if playing == track, let music {
            if !music.isPlaying, prepareSession() { music.play() }
            return
        }
        stopPlayer()
        guard prepareSession(),
              let url = Bundle.main.url(forResource: track.rawValue, withExtension: "caf"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = -1
        player.volume = track.volume
        player.play()
        music = player
        playing = track
    }

    private static func stopPlayer() {
        music?.stop()
        music = nil
        playing = nil
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
