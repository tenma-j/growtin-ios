import Foundation
import SwiftData

// Enregistrements SwiftData. Les objets métier (GrowtinCore) sont stockés sous forme JSON versionnée :
// le schéma de persistance reste stable quand le modèle métier évolue, et la future synchronisation
// avec le backend pourra réutiliser exactement le même format.

@Model
final class ProfileRecord {
    var payload: Data
    var updatedAt: Date

    init(payload: Data, updatedAt: Date = .now) {
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

@Model
final class RoutineItemRecord {
    @Attribute(.unique) var itemID: UUID
    var payload: Data
    var updatedAt: Date

    init(itemID: UUID, payload: Data, updatedAt: Date = .now) {
        self.itemID = itemID
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

@Model
final class CompletionRecord {
    var itemID: UUID
    /// Jour au format AAAA-MM-JJ.
    var dayKey: String
    var completedAt: Date

    init(itemID: UUID, dayKey: String, completedAt: Date = .now) {
        self.itemID = itemID
        self.dayKey = dayKey
        self.completedAt = completedAt
    }
}

@Model
final class CheckInRecord {
    @Attribute(.unique) var dayKey: String
    var payload: Data
    var updatedAt: Date

    init(dayKey: String, payload: Data, updatedAt: Date = .now) {
        self.dayKey = dayKey
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

/// Métadonnées d'une photo de suivi. L'image elle-même est un fichier protégé géré par `PhotoStore`.
@Model
final class PhotoRecord {
    @Attribute(.unique) var photoID: UUID
    var payload: Data
    var updatedAt: Date

    init(photoID: UUID, payload: Data, updatedAt: Date = .now) {
        self.photoID = photoID
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

enum GrowtinSchema {
    static let models: [any PersistentModel.Type] = [
        ProfileRecord.self, RoutineItemRecord.self, CompletionRecord.self, CheckInRecord.self, PhotoRecord.self,
        NutritionStateRecord.self, CoachMessageRecord.self
    ]

    /// Conteneur persistant. Le fichier de base hérite de la protection de données de l'app
    /// (NSFileProtectionComplete, déclarée dans les entitlements) : il est chiffré tant que l'appareil est verrouillé.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Growtin",
            schema: Schema(models),
            isStoredInMemoryOnly: inMemory,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: Schema(models), configurations: configuration)
    }
}
