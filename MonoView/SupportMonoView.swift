import SwiftUI
import StoreKit

struct SupportMonoView: View {
    @ObservedObject var store: SupportStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Label("Support MonoView", systemImage: "heart")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Help us keep improving MonoView.").font(.title3.bold())
                    Text("MonoView is free to use. If it helps you, you can support its development. Your support is optional and does not unlock additional features.")
                        .accessibilityIdentifier("supportOptionalMessage")
                    Text("One-time contribution. No subscription. You may contribute again whenever you choose.")
                        .font(.callout)
                    if !store.canMakePayments {
                        Text("Purchases are disabled on this device. You can continue using every MonoView feature.")
                    } else if store.isLoading && store.products.isEmpty {
                        ProgressView("Loading support options…").frame(maxWidth: .infinity, minHeight: 60)
                    } else if store.products.isEmpty {
                        Text("Support options are unavailable right now. Please try again later. MonoView remains free to use.")
                            .accessibilityIdentifier("supportUnavailable")
                        Button { Task { await store.load() } } label: {
                            Label("Try again", systemImage: "arrow.clockwise").frame(maxWidth: .infinity, minHeight: 52)
                        }.buttonStyle(ControlStyle()).accessibilityIdentifier("supportRetry")
                    } else {
                        VStack(spacing: 12) {
                            ForEach(store.products) { product in
                                supportButton(product)
                            }
                        }
                    }
                    if let message = store.message {
                        Label(message, systemImage: store.thanked ? "checkmark.circle.fill" : "info.circle")
                            .font(.body).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(store.thanked ? "supportThanks" : "supportNotice")
                    }
                    Text("Thank you for being part of MonoView.").font(.callout)
                }
                .frame(maxWidth: 380).padding(24).frame(maxWidth: .infinity)
            }
            Button { dismiss() } label: {
                Text("Done").frame(maxWidth: .infinity, minHeight: 56)
            }.buttonStyle(ControlStyle(primary: true)).padding(16)
                .disabled(store.purchasingID != nil).accessibilityIdentifier("supportDone")
        }
        .foregroundStyle(.white).background(MonoBackground()).tint(.white)
        .preferredColorScheme(.dark).presentationDragIndicator(.visible)
        .interactiveDismissDisabled(store.purchasingID != nil)
        .task { store.startListening(); await store.load() }
        .onChange(of: store.message) { _, message in
            if let message, UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: message)
            }
        }
    }

    private func supportButton(_ product: Product) -> some View {
        let tier = SupportTier.allCases.first { $0.productID == product.id }
        return Button { Task { await store.purchase(product) } } label: {
            VStack(spacing: 6) {
                Text(tier?.title ?? product.displayName).font(.headline)
                if store.purchasingID == product.id {
                    ProgressView("Waiting for Apple…")
                } else if store.pendingIDs.contains(product.id) {
                    Text("Awaiting approval").font(.callout)
                } else {
                    Text(product.displayPrice).font(.title3.bold())
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 72).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(ControlStyle())
        .disabled(store.purchasingID != nil || store.pendingIDs.contains(product.id))
        .accessibilityLabel("\(tier?.title ?? product.displayName), \(product.displayPrice)")
        .accessibilityHint("One-time optional support. Apple will ask you to confirm the purchase.")
        .accessibilityIdentifier("support-\(product.id)")
    }
}
