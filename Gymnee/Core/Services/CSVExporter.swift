import Foundation
import SwiftData

/// CSV エクスポート（§6.8 データ所有権）。全記録をエクスポート可能にする。
@MainActor
enum CSVExporter {
    /// ワークアウト記録（セット単位）を CSV 文字列に変換する。
    static func workoutsCSV(userId: UUID, context: ModelContext) -> String {
        var rows = ["date,workout,exercise,muscle_group,set_index,weight_kg,reps,is_pr"]
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.date)]
        )
        let workouts = (try? context.fetch(descriptor)) ?? []
        let df = ISO8601DateFormatter()
        for workout in workouts {
            for we in workout.exercises.sorted(by: { $0.orderIndex < $1.orderIndex }) {
                for set in we.sets.sorted(by: { $0.setIndex < $1.setIndex }) {
                    let cols: [String] = [
                        df.string(from: workout.date),
                        escape(workout.name),
                        escape(we.exercise?.name ?? ""),
                        we.exercise?.muscleGroup.rawValue ?? "",
                        "\(set.setIndex + 1)",
                        "\(set.weight)",
                        "\(set.reps)",
                        set.isPR ? "1" : "0",
                    ]
                    rows.append(cols.joined(separator: ","))
                }
            }
        }
        return rows.joined(separator: "\n")
    }

    /// 来店記録を CSV に変換する。
    static func visitsCSV(userId: UUID, context: ModelContext) -> String {
        var rows = ["date,gym,chain,note,lat,lng"]
        let descriptor = FetchDescriptor<Visit>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.visitedAt)]
        )
        let visits = (try? context.fetch(descriptor)) ?? []
        let df = ISO8601DateFormatter()
        for v in visits {
            let cols = [
                df.string(from: v.visitedAt),
                escape(v.gym?.name ?? ""),
                escape(v.gym?.chain ?? ""),
                escape(v.note ?? ""),
                v.lat.map { "\($0)" } ?? "",
                v.lng.map { "\($0)" } ?? "",
            ]
            rows.append(cols.joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    /// CSV を一時ファイルに書き出し URL を返す（ShareLink/エクスポート用）。
    static func writeTempFile(_ csv: String, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).csv")
        do {
            try csv.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
