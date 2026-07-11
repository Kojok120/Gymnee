import Foundation
import AVFoundation

/// レスト終了チャイム（RestChime.wav・合成ピング音）の再生。
/// ジムでは端末がサイレントモードのことが多く、通知音（サイレント時は鳴らない）だけでは
/// タイマー終了に気づけないため、フォアグラウンドでは `.playback` カテゴリで再生して
/// サイレントスイッチに関わらず鳴らす。音楽再生中は一瞬だけダッキングする。
/// バックグラウンド時は従来どおりローカル通知の音に委ねる（OS 制約でサイレント時は鳴らない）。
enum RestChime {
    /// 設定トグル（Settings）。未設定は ON。
    static let enabledKey = "gymnee.restSoundEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// 再生中に解放されないよう保持する（短い音なので使い回し）。
    private static var player: AVAudioPlayer?

    static func playIfEnabled() {
        guard isEnabled,
              let url = Bundle.main.url(forResource: "RestChime", withExtension: "wav") else { return }
        do {
            // duckOthers: BGM を止めずに一瞬下げてチャイムを通す。
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.volume = 1.0
            p.play()
            player = p
            // 再生が終わったらセッションを明け渡す（ダッキング解除。音源 0.5s + 余裕）。
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            }
        } catch {
            // 再生失敗は致命ではない（通知・Live Activity が残る）。
        }
    }
}
