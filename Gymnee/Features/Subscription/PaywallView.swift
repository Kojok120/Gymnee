import SwiftUI
import StoreKit

/// Premium への案内（ペイウォール、§4.5）。AI計画など Premium 機能のアップセル。
struct PaywallView: View {
    @Environment(SubscriptionService.self) private var subs
    @Environment(\.dismiss) private var dismiss
    @State private var purchasing = false

    private let features: [(icon: String, title: String, sub: String)] = [
        ("sparkles", "AIワークアウト計画", "予定に合わせて今週のメニューを自動で組み替え"),
        ("calendar", "カレンダー連携", "飲み会や予定を避けて自動リスケジュール"),
        ("chart.line.uptrend.xyaxis", "詳細分析", "ボリューム・部位バランスの深掘り（今後拡充）"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    header
                    featureList
                    plans
                    Button("購入を復元") { Task { await subs.restore(); if subs.isPremium { dismiss() } } }
                        .font(.caption).foregroundStyle(.secondary)
                    Text("サブスクは自動更新されます。いつでも解約可能。")
                        .font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                }
                .padding(Theme.Spacing.lg)
            }
            .navigationTitle("Gymnee Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } } }
            .task { if subs.products.isEmpty { await subs.loadProducts() } }
            .onChange(of: subs.isPremium) { _, premium in if premium { dismiss() } }
        }
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "crown.fill").font(.system(size: 44)).foregroundStyle(Theme.lime)
            Text("もっと続く、もっと伸びる").font(.title2.bold())
            Text("AIと一緒に、予定に合った最適なプランを。").font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.Spacing.lg)
    }

    private var featureList: some View {
        VStack(spacing: Theme.Spacing.md) {
            ForEach(features, id: \.title) { f in
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: f.icon).foregroundStyle(Theme.lime).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.title).font(.subheadline.weight(.semibold))
                        Text(f.sub).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .gymneeCard()
    }

    @ViewBuilder
    private var plans: some View {
        if subs.products.isEmpty {
            VStack(spacing: 6) {
                if subs.isLoading { ProgressView() }
                Text("プランは準備中です。").font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(Theme.Spacing.lg).gymneeCard()
        } else {
            VStack(spacing: Theme.Spacing.md) {
                ForEach(subs.products, id: \.id) { product in
                    Button {
                        purchasing = true
                        Task { await subs.purchase(product); purchasing = false }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.displayName).font(.headline)
                                Text(product.description).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(product.displayPrice).font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(Theme.Spacing.lg)
                        .background(Theme.limeSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(purchasing)
                }
            }
        }
    }
}
