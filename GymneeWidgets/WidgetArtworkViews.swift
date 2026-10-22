import SwiftUI
import UIKit

/// 本体が App Group に置いたドット絵（`WidgetArtwork`）を貼る（issue #155）。
/// 絵が無い（本体をまだ開いていない・App Group が使えない）ときは何も描かない。
struct ArtworkImage: View {
    let fileName: String

    var body: some View {
        if let url = WidgetArtwork.fileURL(fileName), let image = UIImage(contentsOfFile: url.path) {
            // ドット絵なので補間せずに拡大する（にじませない）。
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        }
    }
}

/// ウィジェットのキャラ。しばらく記録が無いと暗くなって「Zzz」と寝ている。
struct WidgetCharacter: View {
    let lastWorkoutDate: Date?
    var now: Date = .now

    var body: some View {
        let sleeping = WidgetArtwork.isSleeping(lastWorkoutDate: lastWorkoutDate, now: now)
        ZStack(alignment: .topTrailing) {
            ArtworkImage(fileName: WidgetArtwork.characterFile)
                .opacity(sleeping ? 0.55 : 1)
            if sleeping {
                Text("Zzz")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 今週のボスの残り HP（パーティに入っていて、今週の値が控えてあるときだけ）。
struct WidgetBossRow: View {
    let boss: WidgetArtwork.Boss

    var body: some View {
        HStack(spacing: 6) {
            ArtworkImage(fileName: WidgetArtwork.bossFile)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(boss.defeated ? "\(boss.name)を倒した！" : boss.name)
                    .font(.caption2.bold())
                    .lineLimit(1)
                if !boss.defeated {
                    ProgressView(value: Double(boss.remainingHP), total: Double(max(1, boss.totalHP)))
                        .tint(.orange)
                    Text("HP \(boss.remainingHP)/\(boss.totalHP)")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
