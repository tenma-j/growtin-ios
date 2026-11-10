import Foundation
import GrowtinCore
import RevenueCat

/// Paramètres RevenueCat. La clé « publique » (appl_…) est conçue pour être embarquée dans l'app.
enum RevenueCatConfiguration {
    static let apiKey = "appl_qAceQtUDpgvLXRZiPTzUCypfJre"
    /// Identifiant du droit d'accès configuré dans RevenueCat.
    static let entitlementID = "premium"

    static var isConfigured: Bool { !apiKey.isEmpty }
}

enum PurchaseOutcome: Equatable {
    case purchased(PremiumStatus)
    case cancelled
}

enum PurchaseError: LocalizedError {
    case notConfigured
    case offerUnavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Les abonnements ne sont pas encore disponibles."
        case .offerUnavailable: "Cette formule n'est plus disponible. Réessaie dans un instant."
        case .failed(let message): message
        }
    }
}

@MainActor
protocol PurchaseServing: AnyObject {
    var isAvailable: Bool { get }
    /// Démarre le service et rattache les achats à l'identifiant du compte serveur (anonyme).
    func start(appUserID: String?) async
    func status() async throws -> PremiumStatus
    func offers() async throws -> [SubscriptionOffer]
    func purchase(offerID: String) async throws -> PurchaseOutcome
    func restore() async throws -> PremiumStatus
    /// Flux des changements d'état (renouvellement, expiration, achat sur un autre appareil).
    func statusUpdates() -> AsyncStream<PremiumStatus>
}

/// Implémentation RevenueCat (StoreKit 2 sous le capot). Les droits sont déterminés par l'entitlement `premium`.
@MainActor
final class RevenueCatPurchaseService: PurchaseServing {
    private var packages: [String: Package] = [:]
    private var started = false

    var isAvailable: Bool { RevenueCatConfiguration.isConfigured }

    func start(appUserID: String?) async {
        guard isAvailable else { return }
        if !started {
            #if DEBUG
            Purchases.logLevel = .debug
            #endif
            Purchases.configure(withAPIKey: RevenueCatConfiguration.apiKey, appUserID: appUserID)
            started = true
        } else if let appUserID, Purchases.shared.appUserID != appUserID {
            _ = try? await Purchases.shared.logIn(appUserID)
        }
    }

    func status() async throws -> PremiumStatus {
        guard started else { throw PurchaseError.notConfigured }
        return Self.status(from: try await Purchases.shared.customerInfo())
    }

    func offers() async throws -> [SubscriptionOffer] {
        guard started else { throw PurchaseError.notConfigured }
        let offerings = try await Purchases.shared.offerings()
        let available = offerings.current?.availablePackages ?? []
        packages = Dictionary(available.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        return available.compactMap(Self.offer(from:)).sorted { $0.period.months > $1.period.months }
    }

    func purchase(offerID: String) async throws -> PurchaseOutcome {
        guard started else { throw PurchaseError.notConfigured }
        guard let package = packages[offerID] else { throw PurchaseError.offerUnavailable }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return .cancelled }
            return .purchased(Self.status(from: result.customerInfo))
        } catch {
            throw PurchaseError.failed("L'achat n'a pas abouti. Aucun montant n'a été prélevé.")
        }
    }

    func restore() async throws -> PremiumStatus {
        guard started else { throw PurchaseError.notConfigured }
        do {
            return Self.status(from: try await Purchases.shared.restorePurchases())
        } catch {
            throw PurchaseError.failed("La restauration des achats a échoué. Vérifie ta connexion et réessaie.")
        }
    }

    func statusUpdates() -> AsyncStream<PremiumStatus> {
        guard started else { return AsyncStream { $0.finish() } }
        let stream = Purchases.shared.customerInfoStream
        return AsyncStream { continuation in
            let task = Task {
                for await info in stream { continuation.yield(Self.status(from: info)) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func status(from info: CustomerInfo) -> PremiumStatus {
        guard let entitlement = info.entitlements[RevenueCatConfiguration.entitlementID], entitlement.isActive else {
            return .free
        }
        return PremiumStatus(isActive: true, expirationDate: entitlement.expirationDate, willRenew: entitlement.willRenew,
                             isTrial: entitlement.periodType == .trial,
                             hasBillingIssue: entitlement.billingIssueDetectedAt != nil)
    }

    private static func offer(from package: Package) -> SubscriptionOffer? {
        let product = package.storeProduct
        guard let period = product.subscriptionPeriod.map(billingPeriod) else { return nil }
        let trial = product.introductoryDiscount.flatMap { discount in
            discount.paymentMode == .freeTrial ? billingPeriod(discount.subscriptionPeriod) : nil
        }
        let title: String
        switch package.packageType {
        case .annual: title = "Annuel"
        case .monthly: title = "Mensuel"
        case .sixMonth: title = "6 mois"
        case .threeMonth: title = "3 mois"
        case .weekly: title = "Hebdomadaire"
        default: title = product.localizedTitle
        }
        return SubscriptionOffer(id: package.identifier, title: title, localizedPrice: product.localizedPriceString,
                                 price: product.price, period: period, freeTrial: trial, currencyCode: product.currencyCode)
    }

    private static func billingPeriod(_ period: SubscriptionPeriod) -> BillingPeriod {
        let unit: BillingPeriod.Unit
        switch period.unit {
        case .day: unit = .day
        case .week: unit = .week
        case .month: unit = .month
        case .year: unit = .year
        @unknown default: unit = .month
        }
        return BillingPeriod(unit: unit, value: period.value)
    }
}

/// Formules fictives pour les aperçus et les captures d'écran automatiques. Aucun achat réel n'est possible.
@MainActor
final class DemoPurchaseService: PurchaseServing {
    var isAvailable: Bool { true }
    private var current = PremiumStatus.free

    func start(appUserID: String?) async {}
    func status() async throws -> PremiumStatus { current }

    func offers() async throws -> [SubscriptionOffer] {
        [SubscriptionOffer(id: "demo-annual", title: "Annuel", localizedPrice: "39,99 €", price: 39.99,
                           period: BillingPeriod(unit: .year, value: 1), freeTrial: BillingPeriod(unit: .day, value: 7), currencyCode: "EUR"),
         SubscriptionOffer(id: "demo-monthly", title: "Mensuel", localizedPrice: "4,99 €", price: 4.99,
                           period: BillingPeriod(unit: .month, value: 1), freeTrial: nil, currencyCode: "EUR")]
    }

    func purchase(offerID: String) async throws -> PurchaseOutcome { .cancelled }
    func restore() async throws -> PremiumStatus { current }
    func statusUpdates() -> AsyncStream<PremiumStatus> { AsyncStream { $0.finish() } }
}
