import Foundation
import Testing
@testable import GrowtinCore

@Suite("Abonnement")
struct SubscriptionTests {
    let monthly = SubscriptionOffer(id: "m", title: "Mensuel", localizedPrice: "4,99 €", price: 4.99,
                                    period: BillingPeriod(unit: .month, value: 1), freeTrial: nil, currencyCode: "EUR")
    let annual = SubscriptionOffer(id: "a", title: "Annuel", localizedPrice: "39,99 €", price: 39.99,
                                   period: BillingPeriod(unit: .year, value: 1), freeTrial: BillingPeriod(unit: .day, value: 7),
                                   currencyCode: "EUR")

    @Test("Libellés de période")
    func periods() {
        #expect(BillingPeriod(unit: .month, value: 1).label == "mois")
        #expect(BillingPeriod(unit: .month, value: 3).label == "3 mois")
        #expect(BillingPeriod(unit: .year, value: 1).label == "an")
        #expect(BillingPeriod(unit: .day, value: 7).durationLabel == "7 jours")
        #expect(monthly.priceLine == "4,99 € / mois")
    }

    @Test("Conditions de renouvellement complètes (règle 3.1.2)")
    func renewalTerms() {
        let terms = annual.renewalTerms
        #expect(terms.contains("Essai gratuit de 7 jours, puis 39,99 € par an"))
        #expect(terms.contains("renouvelle automatiquement"))
        #expect(terms.contains("24 heures"))
        #expect(terms.contains("résilier"))
        #expect(monthly.renewalTerms.hasPrefix("4,99 € par mois."))
    }

    @Test("Économie de la formule annuelle")
    func savings() {
        #expect(annual.savings(comparedTo: monthly) == 33)
        #expect(monthly.savings(comparedTo: annual) == nil)
    }

    @Test("Résumé de l'état d'abonnement")
    func statusSummary() {
        let format: (Date) -> String = { _ in "1 janvier" }
        #expect(PremiumStatus.free.summary(formatter: format) == "Version gratuite")
        #expect(PremiumStatus(isActive: true, expirationDate: .now, willRenew: true, isTrial: true).summary(formatter: format)
                == "Essai gratuit jusqu'au 1 janvier")
        #expect(PremiumStatus(isActive: true, expirationDate: .now, willRenew: false).summary(formatter: format)
                .contains("sans renouvellement"))
        #expect(PremiumStatus(isActive: true, hasBillingIssue: true).summary(formatter: format).contains("paiement"))
    }

    @Test("Les avantages annoncés existent et la sécurité reste gratuite")
    func benefitsAreHonest() {
        #expect(PremiumBenefits.current.contains { $0.id == "coach" })
        #expect(PremiumBenefits.alwaysFree.contains("sécurité"))
    }
}
