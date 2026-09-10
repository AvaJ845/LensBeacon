import Foundation
import StoreKit
import Observation
import os

/// StoreKit 2 wrapper for the single **non-consumable** in-app purchase,
/// "LensBeacon Unlock".
///
/// There is one product, bought once, forever. No subscription, no consumables, no
/// trial gate. Restore Purchases is always available (App Store Review guideline
/// 3.1.2), and because the product is non-consumable, `Transaction.currentEntitlements`
/// is the whole source of truth — the app trusts StoreKit, never a flag it wrote.
///
/// The owned state is mirrored into the App Group so the widget and Live Activity,
/// which cannot call StoreKit, can render locked vs. unlocked content.
@MainActor
@Observable
final class UnlockStore {

    static let productID = "com.avaresearch.lensbeacon.unlock"

    private(set) var product: Product?
    private(set) var isUnlocked: Bool = SharedContainer.isUnlocked
    private(set) var purchaseInFlight = false
    private(set) var loadFailed = false

    /// User-facing price, ready for a button label. Localised by StoreKit.
    var displayPrice: String { product?.displayPrice ?? "$9.99" }

    private var updatesTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.avaresearch.lensbeacon", category: "storekit")

    init() {
        // Start listening for transactions (Ask to Buy approvals, purchases made on
        // another device, refunds) before doing anything else.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(transactionResult: update)
            }
        }
    }

    // No `deinit` cancellation: `UnlockStore` is owned by the `App` for the whole
    // process lifetime, and the listener loop captures `self` weakly, so there is
    // nothing to tear down. (A `@MainActor` deinit also can't touch this property
    // under strict concurrency.)

    // MARK: - Load

    func load() async {
        await refreshEntitlements()
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
            loadFailed = product == nil
        } catch {
            loadFailed = true
            log.error("product load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Purchase / Restore

    enum PurchaseOutcome: Equatable {
        case success
        case pending      // Ask to Buy — approval will arrive via Transaction.updates
        case cancelled
        case failed(String)
    }

    func purchase() async -> PurchaseOutcome {
        guard let product else { return .failed("The App Store isn’t available right now.") }
        guard !purchaseInFlight else { return .failed("A purchase is already in progress.") }
        purchaseInFlight = true
        defer { purchaseInFlight = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                try await finalize(verification)
                return .success
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed("Unexpected App Store response.")
            }
        } catch {
            log.error("purchase failed: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    /// Restore Purchases. `AppStore.sync()` forces a receipt refresh; entitlements
    /// are then re-read. Safe to call any number of times.
    func restore() async -> PurchaseOutcome {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            return isUnlocked ? .success : .failed("No previous purchase was found for this Apple ID.")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Entitlement plumbing

    private func refreshEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        setUnlocked(owned)
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = transactionResult else { return }
        if transaction.productID == Self.productID {
            setUnlocked(transaction.revocationDate == nil)
        }
        await transaction.finish()
    }

    private func finalize(_ verification: VerificationResult<Transaction>) async throws {
        switch verification {
        case .verified(let transaction):
            setUnlocked(transaction.revocationDate == nil)
            await transaction.finish()
        case .unverified(_, let error):
            throw error
        }
    }

    private func setUnlocked(_ value: Bool) {
        guard value != isUnlocked || SharedContainer.isUnlocked != value else {
            isUnlocked = value
            return
        }
        isUnlocked = value
        SharedContainer.isUnlocked = value
    }
}
