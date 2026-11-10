import Foundation
import GrowtinCore
import Observation

/// État de l'abonnement Premium, alimenté par RevenueCat.
@MainActor
@Observable
final class SubscriptionStore {
    private(set) var status = PremiumStatus.free
    private(set) var offers: [SubscriptionOffer] = []
    private(set) var isLoading = false
    private(set) var isPurchasing = false
    var message: String?

    let service: PurchaseServing
    private var updatesTask: Task<Void, Never>?

    init(service: PurchaseServing) {
        self.service = service
    }

    var isAvailable: Bool { service.isAvailable }

    /// Démarre RevenueCat avec l'identifiant du compte serveur, puis écoute les changements d'état.
    func start(appUserID: String?) async {
        guard service.isAvailable else { return }
        await service.start(appUserID: appUserID)
        if let current = try? await service.status() { status = current }
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            guard let stream = self?.service.statusUpdates() else { return }
            for await update in stream { self?.status = update }
        }
    }

    func loadOffers() async {
        guard service.isAvailable, offers.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            offers = try await service.offers()
            if offers.isEmpty { message = "Aucune formule n'est disponible pour le moment." }
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "Les formules n'ont pas pu être chargées."
        }
    }

    /// Retourne `true` si l'achat a abouti.
    func purchase(_ offer: SubscriptionOffer) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await service.purchase(offerID: offer.id) {
            case .purchased(let newStatus):
                status = newStatus
                return newStatus.isActive
            case .cancelled:
                return false
            }
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "L'achat n'a pas abouti."
            return false
        }
    }

    func restore() async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            status = try await service.restore()
            message = status.isActive ? "Ton abonnement Premium a été restauré." : "Aucun abonnement actif n'a été trouvé pour ce compte Apple."
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "La restauration a échoué."
        }
    }
}
