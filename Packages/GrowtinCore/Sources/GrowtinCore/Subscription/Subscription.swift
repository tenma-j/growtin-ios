import Foundation

/// Période d'un abonnement, indépendante de StoreKit et de RevenueCat.
public struct BillingPeriod: Hashable, Sendable {
    public enum Unit: Sendable { case day, week, month, year }

    public let unit: Unit
    public let value: Int

    public init(unit: Unit, value: Int) {
        self.unit = unit
        self.value = max(1, value)
    }

    /// « mois », « 3 mois », « an », « semaine »…
    public var label: String {
        switch (unit, value) {
        case (.day, 1): "jour"
        case (.day, _): "\(value) jours"
        case (.week, 1): "semaine"
        case (.week, _): "\(value) semaines"
        case (.month, 1): "mois"
        case (.month, _): "\(value) mois"
        case (.year, 1): "an"
        case (.year, _): "\(value) ans"
        }
    }

    /// Durée d'un essai : « 7 jours », « 1 mois ».
    public var durationLabel: String {
        switch unit {
        case .day: "\(value) jour\(value > 1 ? "s" : "")"
        case .week: "\(value) semaine\(value > 1 ? "s" : "")"
        case .month: "\(value) mois"
        case .year: "\(value) an\(value > 1 ? "s" : "")"
        }
    }

    /// Nombre approximatif de mois, pour comparer les formules.
    public var months: Double {
        switch unit {
        case .day: Double(value) / 30.0
        case .week: Double(value) * 7 / 30.0
        case .month: Double(value)
        case .year: Double(value) * 12
        }
    }
}

/// Formule d'abonnement prête à afficher (prix déjà localisés par l'App Store).
public struct SubscriptionOffer: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let localizedPrice: String
    public let price: Decimal
    public let period: BillingPeriod
    public let freeTrial: BillingPeriod?
    public let currencyCode: String?

    public init(id: String, title: String, localizedPrice: String, price: Decimal, period: BillingPeriod,
                freeTrial: BillingPeriod?, currencyCode: String?) {
        self.id = id
        self.title = title
        self.localizedPrice = localizedPrice
        self.price = price
        self.period = period
        self.freeTrial = freeTrial
        self.currencyCode = currencyCode
    }

    /// « 4,99 € / mois »
    public var priceLine: String { "\(localizedPrice) / \(period.label)" }

    /// Texte de renouvellement exigé par Apple (règle 3.1.2) : montant, période, essai, résiliation.
    public var renewalTerms: String {
        var text = ""
        if let freeTrial {
            text += "Essai gratuit de \(freeTrial.durationLabel), puis \(localizedPrice) par \(period.label). "
        } else {
            text += "\(localizedPrice) par \(period.label). "
        }
        text += "L'abonnement se renouvelle automatiquement, sauf résiliation au moins 24 heures avant la fin de la période en cours. "
        text += "Le paiement est prélevé sur ton compte Apple à la confirmation de l'achat"
        text += freeTrial == nil ? "." : ", à la fin de l'essai."
        text += " Tu peux gérer ou résilier l'abonnement dans les réglages de ton compte Apple."
        return text
    }

    /// Économie de cette formule par rapport à une autre, en pourcentage entier (nil si aucune économie).
    public func savings(comparedTo other: SubscriptionOffer) -> Int? {
        guard period.months > other.period.months, other.period.months > 0, other.price > 0 else { return nil }
        let monthlyHere = (price as NSDecimalNumber).doubleValue / period.months
        let monthlyOther = (other.price as NSDecimalNumber).doubleValue / other.period.months
        let saving = 1 - monthlyHere / monthlyOther
        guard saving >= 0.05 else { return nil }
        return Int((saving * 100).rounded(.down))
    }
}

/// État de l'abonnement de l'utilisateur.
public struct PremiumStatus: Hashable, Sendable {
    public let isActive: Bool
    public let expirationDate: Date?
    public let willRenew: Bool
    public let isTrial: Bool
    /// Problème de paiement détecté : l'accès est maintenu pendant la période de grâce d'Apple.
    public let hasBillingIssue: Bool

    public init(isActive: Bool, expirationDate: Date? = nil, willRenew: Bool = false, isTrial: Bool = false, hasBillingIssue: Bool = false) {
        self.isActive = isActive
        self.expirationDate = expirationDate
        self.willRenew = willRenew
        self.isTrial = isTrial
        self.hasBillingIssue = hasBillingIssue
    }

    public static let free = PremiumStatus(isActive: false)

    public func summary(formatter: (Date) -> String) -> String {
        guard isActive else { return "Version gratuite" }
        if hasBillingIssue { return "Premium — problème de paiement à régler dans les réglages Apple" }
        guard let expirationDate else { return "Premium actif" }
        let date = formatter(expirationDate)
        if isTrial { return willRenew ? "Essai gratuit jusqu'au \(date)" : "Essai gratuit, se termine le \(date)" }
        return willRenew ? "Premium, renouvellement le \(date)" : "Premium jusqu'au \(date), sans renouvellement"
    }
}

/// Ce que Premium apporte réellement aujourd'hui. Ne lister ici que des avantages effectivement disponibles.
public enum PremiumBenefits {
    public struct Benefit: Hashable, Sendable, Identifiable {
        public let id: String
        public let symbol: String
        public let title: String
        public let detail: String
    }

    public static let current: [Benefit] = [
        Benefit(id: "coach", symbol: "sparkles", title: "Coach : 40 questions par jour",
                detail: "Au lieu de 5 en version gratuite, avec des réponses personnalisées et sourcées."),
        Benefit(id: "support", symbol: "heart", title: "Soutenir Growtin'",
                detail: "Ton abonnement finance le Coach, les nouvelles recettes et les prochaines fonctionnalités.")
    ]

    /// Ce qui reste toujours gratuit : la sécurité et l'essentiel du suivi ne sont jamais réservés aux abonnés.
    public static let alwaysFree = "Routine, suivi photo, nutrition, séances, bibliothèque, et toutes les informations de sécurité restent gratuits."
}
