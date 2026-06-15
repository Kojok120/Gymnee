import Foundation

/// 決済プロバイダ抽象（§6.12）。物理グッズは外部決済（Stripe）。
/// v0 は鍵不要の Stub。Stripe 実装は同 protocol 準拠で後差し込み（§9-5 サブスクは別判断・保留）。
protocol PaymentProvider: Sendable {
    /// 金額を決済し、決済 ID（payment_intent 相当）を返す。
    func charge(amount: Decimal, currency: String) async throws -> String
}

enum PaymentError: Error { case declined }

/// ローカル検証用のスタブ決済（常に成功し、ダミーの payment_intent を返す）。
struct StubPaymentProvider: PaymentProvider {
    func charge(amount: Decimal, currency: String) async throws -> String {
        // 実決済のネットワーク往復を模した短い待機。
        try? await Task.sleep(nanoseconds: 400_000_000)
        return "stub_pi_" + UUID().uuidString.prefix(12)
    }
}
