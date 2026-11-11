import Foundation
import GrowtinCore
import Observation
import SwiftData

@Model
final class CoachMessageRecord {
    @Attribute(.unique) var messageID: UUID
    var payload: Data
    var createdAt: Date

    init(messageID: UUID, payload: Data, createdAt: Date) {
        self.messageID = messageID
        self.payload = payload
        self.createdAt = createdAt
    }
}

/// Conversation avec le Coach. L'historique reste sur l'iPhone : le serveur ne conserve aucun message.
@MainActor
@Observable
final class CoachStore {
    private(set) var messages: [CoachMessage] = []
    private(set) var isSending = false
    private(set) var quota: CoachQuota?
    private(set) var alerts: [SafetyAlert] = []
    var error: CoachError?

    let service: CoachServing
    private let context: ModelContext

    init(context: ModelContext, service: CoachServing) {
        self.context = context
        self.service = service
    }

    /// Une lecture de photo compte dans le même quota quotidien que les questions.
    func updateQuota(_ newQuota: CoachQuota?) {
        if let newQuota { quota = newQuota }
    }

    func load() {
        let records = (try? context.fetch(FetchDescriptor<CoachMessageRecord>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        messages = records.compactMap { try? JSONDecoder().decode(CoachMessage.self, from: $0.payload) }
    }

    /// Envoie une question. `contextProvider` n'est appelé que si la personnalisation est activée.
    func send(_ text: String, personalization: Bool, contextProvider: () -> String) async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSending else { return }
        error = nil
        append(CoachMessage(role: .user, content: question))

        // Signaux d'alerte détectés sur l'appareil, avant tout envoi.
        alerts = SafetyScreener().assess(text: question)
        if alerts.contains(where: { $0.level == .seekHelpNow }) {
            append(CoachMessage(role: .assistant, content: SafetyScreener.distressAlert.message, isLocal: true))
            return
        }

        isSending = true
        defer { isSending = false }
        do {
            let reply = try await service.send(messages, context: personalization ? contextProvider() : "", personalization: personalization)
            quota = reply.quota ?? quota
            append(CoachMessage(role: .assistant, content: reply.message, citations: reply.citations))
        } catch let coachError as CoachError {
            if case .quotaReached(let newQuota) = coachError { quota = newQuota ?? quota }
            error = coachError
        } catch {
            self.error = .network
        }
    }

    func clearConversation() {
        try? context.delete(model: CoachMessageRecord.self)
        try? context.save()
        messages = []
        alerts = []
        error = nil
    }

    /// Supprime la conversation locale et le compte serveur.
    func deleteEverything() async {
        clearConversation()
        try? await service.deleteAccount()
        quota = nil
    }

    private func append(_ message: CoachMessage) {
        messages.append(message)
        if let payload = try? JSONEncoder().encode(message) {
            context.insert(CoachMessageRecord(messageID: message.id, payload: payload, createdAt: message.createdAt))
            try? context.save()
        }
    }

    #if DEBUG
    /// Conversation de démonstration pour les captures d'écran.
    func seedDemo() {
        clearConversation()
        append(CoachMessage(role: .user, content: "Est-ce que mieux dormir peut m'aider ?", isLocal: true))
        append(CoachMessage(
            role: .assistant,
            content: "Réponse de démonstration. Tu as indiqué dormir environ six heures par nuit. Viser au moins 7 heures, avec un horaire de coucher régulier, est bénéfique pour ton bien-être général [S:watson-2015-sleep]. En revanche, cela ne constitue pas un traitement démontré contre l'alopécie androgénétique.",
            citations: ["watson-2015-sleep"], isLocal: true))
        quota = CoachQuota(used: 1, limit: 2, premium: false)
    }
    #endif
}
