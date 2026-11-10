import Foundation
import GrowtinCore
import Observation
import OSLog
import SwiftData

/// État central de l'application et point d'accès unique aux données locales.
/// Les vues lisent des valeurs métier (GrowtinCore) et n'accèdent jamais directement à SwiftData.
@MainActor
@Observable
final class AppModel {
    private(set) var profile: UserProfile?
    private(set) var routine: [RoutineItem] = []
    private(set) var completions: [HabitCompletion] = []
    private(set) var checkIns: [DayKey: DailyCheckIn] = [:]
    private(set) var photos: [PhotoEntry] = []
    private(set) var isLoaded = false
    var lastError: AppError?

    let library: SourceLibrary
    let notifications: NotificationScheduling
    let photoStore: PhotoStore
    let nutrition: NutritionStore
    let coach: CoachStore
    let subscription: SubscriptionStore
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger = Logger(subsystem: "app.growtin", category: "AppModel")

    struct AppError: Identifiable, Equatable {
        let id = UUID()
        let message: String
    }

    init(container: ModelContainer, notifications: NotificationScheduling, photoStore: PhotoStore, coachService: CoachServing,
         purchaseService: PurchaseServing) {
        self.context = container.mainContext
        self.notifications = notifications
        self.photoStore = photoStore
        self.nutrition = NutritionStore(context: container.mainContext)
        self.coach = CoachStore(context: container.mainContext, service: coachService)
        self.subscription = SubscriptionStore(service: purchaseService)
        do {
            library = try SourceLibrary.bundled()
        } catch {
            // La base embarquée est validée par les tests : cette branche signale un défaut de packaging.
            Logger(subsystem: "app.growtin", category: "AppModel").fault("Base documentaire illisible : \(String(describing: error))")
            library = try! SourceLibrary(sources: [])
        }
    }

    // MARK: - Chargement

    func load() {
        do {
            if let record = try context.fetch(FetchDescriptor<ProfileRecord>()).first {
                profile = try decoder.decode(UserProfile.self, from: record.payload)
            }
            routine = try context.fetch(FetchDescriptor<RoutineItemRecord>())
                .compactMap { try? decoder.decode(RoutineItem.self, from: $0.payload) }
                .sorted { $0.minuteOfDay < $1.minuteOfDay }
            completions = try context.fetch(FetchDescriptor<CompletionRecord>()).compactMap { record in
                DayKey(string: record.dayKey).map { HabitCompletion(itemID: record.itemID, day: $0, completedAt: record.completedAt) }
            }
            let checkInPairs: [(DayKey, DailyCheckIn)] = try context.fetch(FetchDescriptor<CheckInRecord>()).compactMap { record in
                guard let day = DayKey(string: record.dayKey),
                      let checkIn = try? decoder.decode(DailyCheckIn.self, from: record.payload) else { return nil }
                return (day, checkIn)
            }
            checkIns = Dictionary(checkInPairs, uniquingKeysWith: { _, latest in latest })
            photos = try context.fetch(FetchDescriptor<PhotoRecord>())
                .compactMap { try? decoder.decode(PhotoEntry.self, from: $0.payload) }
                .sorted { $0.takenAt < $1.takenAt }
            nutrition.load()
            coach.load()
        } catch {
            report(error, message: "Impossible de charger tes données.")
        }
        isLoaded = true
    }

    // MARK: - Lectures dérivées

    var activeRoutine: [RoutineItem] { routine.filter(\.isActive) }

    var consistency: ConsistencyCalculator { ConsistencyCalculator(items: routine, completions: completions) }

    var profileAlerts: [SafetyAlert] { profile.map { SafetyScreener().assess(profile: $0) } ?? [] }

    func alerts(for day: DayKey) -> [SafetyAlert] {
        let fromText = checkIns[day].map { SafetyScreener().assess(text: $0.note) } ?? []
        let combined = fromText + profileAlerts.filter { $0.level >= .consultDoctor }
        var seen = Set<String>()
        return combined.filter { seen.insert($0.id).inserted }.sorted { $0.level > $1.level }
    }

    var programStart: DayKey { DayKey(profile?.programStartDate ?? .now) }

    // MARK: - Onboarding et profil

    func completeOnboarding(with profile: UserProfile) {
        let today = DayKey(.now)
        var profile = profile
        profile.programStartDate = .now
        let items = RoutineEngine().initialRoutine(for: profile, startingOn: today)
        do {
            try persist(profile: profile)
            for item in items { try upsert(item) }
            try context.save()
            self.profile = profile
            self.routine = items
        } catch {
            context.rollback()
            report(error, message: "Ton programme n'a pas pu être enregistré. Réessaie.")
        }
    }

    /// Met à jour les réponses. Si demandé, les habitudes proposées par Growtin' sont recalculées ;
    /// les habitudes personnelles et l'historique sont conservés.
    func updateProfile(_ newProfile: UserProfile, regenerateRoutine: Bool) {
        do {
            try persist(profile: newProfile)
            if regenerateRoutine {
                let today = DayKey(.now)
                let proposed = RoutineEngine().initialRoutine(for: newProfile, startingOn: today)
                let proposedIDs = Set(proposed.compactMap(\.templateID))
                var updated = routine
                // Retire les habitudes Growtin' qui ne sont plus proposées.
                for index in updated.indices where updated[index].isActive {
                    if let templateID = updated[index].templateID, !proposedIDs.contains(templateID) {
                        updated[index].removedOn = today
                    }
                }
                // Ajoute les nouvelles, met à jour la raison des existantes.
                for item in proposed {
                    if let index = updated.firstIndex(where: { $0.isActive && $0.templateID == item.templateID }) {
                        updated[index].reason = item.reason
                    } else {
                        updated.append(item)
                    }
                }
                for item in updated { try upsert(item) }
                routine = updated.sorted { $0.minuteOfDay < $1.minuteOfDay }
                Task { await rescheduleReminders() }
            }
            try context.save()
            profile = newProfile
        } catch {
            context.rollback()
            report(error, message: "Tes réponses n'ont pas pu être enregistrées.")
        }
    }

    func updatePhotoFrequency(_ frequency: PhotoFrequency) {
        guard var profile else { return }
        profile.photoFrequency = frequency
        updateProfile(profile, regenerateRoutine: false)
    }

    func setAIPersonalization(_ enabled: Bool) {
        guard var profile else { return }
        profile.consents.aiPersonalization = enabled
        updateProfile(profile, regenerateRoutine: false)
    }

    // MARK: - Routine

    func isCompleted(_ item: RoutineItem, on day: DayKey) -> Bool {
        consistency.isCompleted(item, on: day)
    }

    func setCompleted(_ completed: Bool, item: RoutineItem, on day: DayKey) {
        do {
            let key = day.description
            let itemID = item.id
            let existing = try context.fetch(FetchDescriptor<CompletionRecord>(
                predicate: #Predicate { $0.itemID == itemID && $0.dayKey == key }))
            if completed, existing.isEmpty {
                context.insert(CompletionRecord(itemID: item.id, dayKey: key))
                completions.append(HabitCompletion(itemID: item.id, day: day))
            } else if !completed {
                for record in existing { context.delete(record) }
                completions.removeAll { $0.itemID == item.id && $0.day == day }
            }
            try context.save()
        } catch {
            context.rollback()
            report(error, message: "Impossible d'enregistrer cette habitude.")
        }
    }

    func addHabit(template: HabitTemplate) {
        save(RoutineItem(template: template, reason: nil, addedOn: DayKey(.now)), isNew: true)
    }

    func addCustomHabit(title: String, minuteOfDay: Int) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        save(RoutineItem(templateID: nil, title: trimmed, detail: "Habitude personnelle", symbol: "star",
                         minuteOfDay: minuteOfDay, addedOn: DayKey(.now)), isNew: true)
    }

    func update(_ item: RoutineItem) {
        save(item, isNew: false)
    }

    /// Retire l'habitude à partir d'aujourd'hui : l'historique des jours précédents reste intact.
    func remove(_ item: RoutineItem) {
        var removed = item
        removed.removedOn = DayKey(.now)
        removed.reminderEnabled = false
        save(removed, isNew: false)
    }

    private func save(_ item: RoutineItem, isNew: Bool) {
        do {
            try upsert(item)
            try context.save()
            if let index = routine.firstIndex(where: { $0.id == item.id }) {
                routine[index] = item
            } else {
                routine.append(item)
            }
            routine.sort { $0.minuteOfDay < $1.minuteOfDay }
            Task { await rescheduleReminders() }
        } catch {
            context.rollback()
            report(error, message: isNew ? "Impossible d'ajouter cette habitude." : "Impossible de modifier cette habitude.")
        }
    }

    func rescheduleReminders() async {
        await notifications.syncDailyReminders(for: activeRoutine.filter(\.reminderEnabled))
    }

    // MARK: - Bilan du jour

    func saveCheckIn(_ checkIn: DailyCheckIn) {
        do {
            let key = checkIn.day.description
            let payload = try encoder.encode(checkIn)
            if let record = try context.fetch(FetchDescriptor<CheckInRecord>(predicate: #Predicate { $0.dayKey == key })).first {
                record.payload = payload
                record.updatedAt = .now
            } else {
                context.insert(CheckInRecord(dayKey: key, payload: payload))
            }
            try context.save()
            checkIns[checkIn.day] = checkIn
        } catch {
            context.rollback()
            report(error, message: "Ton bilan n'a pas pu être enregistré.")
            return
        }
        if let item = activeRoutine.first(where: { $0.kind == .checkIn }), !checkIn.isEmpty {
            setCompleted(true, item: item, on: checkIn.day)
        }
    }

    // MARK: - Services en ligne

    /// Démarre l'abonnement (si RevenueCat est configuré) en le rattachant au compte serveur anonyme,
    /// pour que le serveur sache quels utilisateurs sont Premium.
    func startOnlineServices() async {
        guard subscription.isAvailable else { return }
        let userID = await coach.service.backendUserID()
        await subscription.start(appUserID: userID)
    }

    // MARK: - Coach

    func acceptCoachConsent(personalization: Bool) {
        guard var profile else { return }
        profile.consents.coachConsentAt = .now
        profile.consents.aiPersonalization = personalization
        updateProfile(profile, regenerateRoutine: false)
    }

    func revokeCoachConsent() {
        guard var profile else { return }
        profile.consents.coachConsentAt = nil
        updateProfile(profile, regenerateRoutine: false)
    }

    /// Contexte transmis au Coach, construit uniquement à la demande et si la personnalisation est activée.
    func coachContext() -> String {
        guard let profile, profile.consents.aiPersonalization else { return "" }
        let today = DayKey(.now)
        return CoachContextBuilder.build(profile: profile, routine: routine,
                                         consistency7Days: consistency.consistency(endingOn: today, days: 7),
                                         checkIns: Array(checkIns.values), photoCount: photos.count, today: today)
    }

    // MARK: - Photos

    var lastPhotoDay: DayKey? { PhotoTimeline.lastSessionDay(photos) }

    var photoZones: [PhotoZone] { PhotoZone.suggested(for: profile?.zones ?? []) }

    func photos(for zone: PhotoZone) -> [PhotoEntry] { PhotoTimeline.photos(photos, zone: zone) }

    func photo(id: UUID) -> PhotoEntry? { photos.first { $0.id == id } }

    /// Enregistre une photo (fichier protégé + métadonnées). Retourne `false` en cas d'échec.
    @discardableResult
    func addPhoto(jpegData: Data, zone: PhotoZone, camera: CameraPosition, quality: ImageQuality?,
                  conditions: CaptureConditions, framing: FramingInfo, takenAt: Date = .now) -> Bool {
        let id = UUID()
        do {
            let fileName = try photoStore.save(jpegData, id: id)
            let entry = PhotoEntry(id: id, zone: zone, day: DayKey(takenAt), takenAt: takenAt, fileName: fileName,
                                   camera: camera, quality: quality, conditions: conditions, framing: framing)
            context.insert(PhotoRecord(photoID: id, payload: try encoder.encode(entry)))
            try context.save()
            photos.append(entry)
            photos.sort { $0.takenAt < $1.takenAt }
            return true
        } catch {
            context.rollback()
            photoStore.delete(fileName: "\(id.uuidString).jpg")
            report(error, message: "La photo n'a pas pu être enregistrée.")
            return false
        }
    }

    func deletePhoto(_ entry: PhotoEntry) {
        do {
            let id = entry.id
            for record in try context.fetch(FetchDescriptor<PhotoRecord>(predicate: #Predicate { $0.photoID == id })) {
                context.delete(record)
            }
            try context.save()
            photoStore.delete(fileName: entry.fileName)
            photos.removeAll { $0.id == entry.id }
        } catch {
            context.rollback()
            report(error, message: "La photo n'a pas pu être supprimée.")
        }
    }

    // MARK: - Suppression

    /// Supprime définitivement toutes les données locales et les rappels programmés.
    func deleteAllData() async {
        do {
            try context.delete(model: ProfileRecord.self)
            try context.delete(model: RoutineItemRecord.self)
            try context.delete(model: CompletionRecord.self)
            try context.delete(model: CheckInRecord.self)
            try context.delete(model: PhotoRecord.self)
            try context.delete(model: NutritionStateRecord.self)
            try context.delete(model: CoachMessageRecord.self)
            try context.save()
        } catch {
            context.rollback()
            report(error, message: "La suppression n'a pas abouti. Réessaie.")
            return
        }
        await notifications.removeAll()
        await coach.deleteEverything()
        photoStore.deleteAll()
        nutrition.reset()
        photos = []
        profile = nil
        routine = []
        completions = []
        checkIns = [:]
    }

    // MARK: - Démonstration (versions de développement uniquement)

    #if DEBUG
    /// Remplace les données par un jeu de démonstration. Utilisé uniquement pour les aperçus et
    /// les captures d'écran automatiques ; n'existe pas dans la version publiée.
    func importDemoData(profile: UserProfile, routine: [RoutineItem], completions: [HabitCompletion], checkIns: [DailyCheckIn]) {
        do {
            try persist(profile: profile)
            for item in routine { try upsert(item) }
            for completion in completions {
                context.insert(CompletionRecord(itemID: completion.itemID, dayKey: completion.day.description,
                                                completedAt: completion.completedAt))
            }
            for checkIn in checkIns {
                context.insert(CheckInRecord(dayKey: checkIn.day.description, payload: try encoder.encode(checkIn)))
            }
            try context.save()
            self.profile = profile
            self.routine = routine.sorted { $0.minuteOfDay < $1.minuteOfDay }
            self.completions = completions
            self.checkIns = Dictionary(checkIns.map { ($0.day, $0) }, uniquingKeysWith: { _, latest in latest })
        } catch {
            report(error, message: "Données de démonstration invalides.")
        }
    }
    #endif

    // MARK: - Privé

    private func persist(profile: UserProfile) throws {
        let payload = try encoder.encode(profile)
        if let record = try context.fetch(FetchDescriptor<ProfileRecord>()).first {
            record.payload = payload
            record.updatedAt = .now
        } else {
            context.insert(ProfileRecord(payload: payload))
        }
    }

    private func upsert(_ item: RoutineItem) throws {
        let payload = try encoder.encode(item)
        let itemID = item.id
        if let record = try context.fetch(FetchDescriptor<RoutineItemRecord>(predicate: #Predicate { $0.itemID == itemID })).first {
            record.payload = payload
            record.updatedAt = .now
        } else {
            context.insert(RoutineItemRecord(itemID: item.id, payload: payload))
        }
    }

    private func report(_ error: Error, message: String) {
        logger.error("\(message, privacy: .public) \(String(describing: error), privacy: .private)")
        lastError = AppError(message: message)
    }
}
