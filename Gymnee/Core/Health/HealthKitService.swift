import Foundation
import HealthKit
import Observation

/// HealthKit 連携（§6.9）。体重・体組成の読込、ワークアウトの書き戻し。最小権限・用途明示。
/// 許諾なし／非対応端末でも縮退動作（呼び出しは安全に no-op）。
/// ※ 実機での動作には HealthKit エンタイトルメント＋ Capability の付与が必要（有償アカウント整備後）。
@MainActor
@Observable
final class HealthKitService {
    private let store = HKHealthStore()
    private(set) var isAuthorized = false

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var set = Set<HKObjectType>()
        if let bm = HKObjectType.quantityType(forIdentifier: .bodyMass) { set.insert(bm) }
        if let bf = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage) { set.insert(bf) }
        return set
    }

    private var writeTypes: Set<HKSampleType> {
        var set = Set<HKSampleType>()
        if let bm = HKObjectType.quantityType(forIdentifier: .bodyMass) { set.insert(bm) }
        set.insert(HKObjectType.workoutType())
        return set
    }

    /// 許諾を要求（最小権限）。
    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true
        } catch {
            isAuthorized = false
        }
    }

    /// 最新の体重（kg）を読む。
    func latestBodyMass() async -> Double? {
        await latestQuantity(.bodyMass, unit: .gramUnit(with: .kilo))
    }

    /// 最新の体脂肪率（%）を読む。
    func latestBodyFat() async -> Double? {
        await latestQuantity(.bodyFatPercentage, unit: .percent()).map { $0 * 100 }
    }

    private func latestQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard isAvailable, let type = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    /// 体重を書き込む（双方向同期、§6.7）。
    func saveBodyMass(_ kg: Double, date: Date = .now) async {
        guard isAvailable, isAuthorized, let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return }
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
        try? await store.save(sample)
    }

    /// ワークアウトをヘルスケアへ書き戻す（種別・時間、§6.9）。
    func saveWorkout(start: Date, end: Date, activeEnergyKcal: Double? = nil) async {
        guard isAvailable, isAuthorized else { return }
        let builder = HKWorkoutBuilder(healthStore: store, configuration: {
            let c = HKWorkoutConfiguration()
            c.activityType = .traditionalStrengthTraining
            return c
        }(), device: .local())
        do {
            try await builder.beginCollection(at: start)
            if let activeEnergyKcal, let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
                let sample = HKQuantitySample(
                    type: energyType,
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: activeEnergyKcal),
                    start: start, end: end
                )
                try await builder.addSamples([sample])
            }
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            // 失敗は無視（縮退）。
        }
    }
}
