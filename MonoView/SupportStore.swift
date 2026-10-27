import StoreKit
import Combine

nonisolated enum SupportTier: String, CaseIterable, Sendable {
    case small, development, extra
    var productID: String { "com.monoview.support.\(rawValue)" }
    var title: String {
        switch self {
        case .small: "Small support"
        case .development: "Support development"
        case .extra: "Extra support"
        }
    }
    static var productIDs: Set<String> { Set(allCases.map(\.productID)) }
}

/// Consumable tips have no entitlements and never gate any MonoView feature.
@MainActor final class SupportStore: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = false
    @Published private(set) var purchasingID: String?
    @Published private(set) var pendingIDs: Set<String> = []
    @Published private(set) var message: String?
    @Published private(set) var thanked = false
    private var updatesTask: Task<Void, Never>?
    private var handledIDs: Set<UInt64> = []
    var canMakePayments: Bool { AppStore.canMakePayments }

    func startListening() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard !Task.isCancelled else { return }
                await self?.handle(result)
            }
        }
        Task { [weak self] in
            for await result in StoreKit.Transaction.unfinished {
                guard !Task.isCancelled else { return }
                await self?.handle(result)
            }
        }
    }
    deinit { updatesTask?.cancel() }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: SupportTier.productIDs)
            guard !Task.isCancelled else { return }
            products = SupportTier.allCases.compactMap { tier in
                loaded.first { $0.id == tier.productID && $0.type == .consumable }
            }
        } catch {
            if !Task.isCancelled { products = [] }
        }
    }

    func purchase(_ product: Product) async {
        guard purchasingID == nil, canMakePayments, !pendingIDs.contains(product.id),
              SupportTier.productIDs.contains(product.id), product.type == .consumable else { return }
        startListening()
        purchasingID = product.id
        message = nil
        thanked = false
        defer { purchasingID = nil }
        do {
            switch try await product.purchase() {
            case .success(let result): await handle(result)
            case .pending:
                pendingIDs.insert(product.id)
                message = "Your support is awaiting approval. You can keep using every MonoView feature."
            case .userCancelled: break
            @unknown default:
                message = "The purchase could not be completed. Please try again later."
            }
        } catch StoreKitError.userCancelled {
            // Cancellation is an ordinary exit from Apple’s purchase sheet.
        } catch let error as SKError where error.code == .paymentCancelled {
            // StoreKit may bridge cancellation through the legacy error domain.
        } catch {
            message = "Apple could not complete the purchase. Please try again later. All MonoView features remain available."
        }
    }

    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
        switch result {
        case .verified(let transaction):
            guard SupportTier.productIDs.contains(transaction.productID), transaction.productType == .consumable else { return }
            let first = handledIDs.insert(transaction.id).inserted
            pendingIDs.remove(transaction.productID)
            if first && transaction.revocationDate == nil {
                thanked = true
                message = "Thank you for supporting MonoView. Your contribution helps us improve the app for everyone."
            }
            await transaction.finish()
        case .unverified(let transaction, _):
            guard SupportTier.productIDs.contains(transaction.productID) else { return }
            thanked = false
            message = "Your purchase could not be verified. Please check your Apple purchase history before trying again."
        }
    }
}
