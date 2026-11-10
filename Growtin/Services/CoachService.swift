import Foundation
import GrowtinCore
import Security

/// Paramètres publics du backend. L'URL et la clé « anon » de Supabase sont conçues pour être embarquées
/// dans une app : elles ne donnent accès qu'à ce que les règles de sécurité autorisent.
/// La clé Anthropic, elle, n'existe que côté serveur.
enum BackendConfiguration {
    static let supabaseURL = "https://hxaioqwdqtuxlodfhfxg.supabase.co"
    /// Clé « publishable » (nouveau format des clés anon) : publique par conception.
    static let supabaseAnonKey = "sb_publishable_-UyhWHaBgQcs8WFV71D0MQ_AmxDArss"

    static var isConfigured: Bool { !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty }
}

struct CoachReply: Decodable {
    let message: String
    let citations: [String]
    let safety: String
    let quota: CoachQuota?
}

enum CoachError: LocalizedError, Equatable {
    case notConfigured
    case quotaReached(CoachQuota?)
    case network
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Le Coach n'est pas encore relié à son serveur."
        case .quotaReached: "Tu as atteint la limite de questions pour aujourd'hui. Reviens demain !"
        case .network: "Connexion impossible. Vérifie ta connexion à Internet."
        case .server(let message): message
        }
    }
}

@MainActor
protocol CoachServing: AnyObject {
    var isAvailable: Bool { get }
    func send(_ messages: [CoachMessage], context: String, personalization: Bool) async throws -> CoachReply
    /// Supprime le compte serveur (anonyme) et ses compteurs. Sans effet si aucun compte n'existe.
    func deleteAccount() async throws
}

/// Implémentation réelle : session Supabase anonyme, puis fonction serveur « coach ».
@MainActor
final class SupabaseCoachService: CoachServing {
    private let baseURL: URL?
    private let anonKey: String
    private let session: URLSession
    private let keychain = KeychainStore(service: "app.growtin.backend")

    init(urlString: String = BackendConfiguration.supabaseURL, anonKey: String = BackendConfiguration.supabaseAnonKey,
         session: URLSession = .shared) {
        self.baseURL = URL(string: urlString)
        self.anonKey = anonKey
        self.session = session
    }

    var isAvailable: Bool { baseURL != nil && !anonKey.isEmpty }

    func send(_ messages: [CoachMessage], context: String, personalization: Bool) async throws -> CoachReply {
        guard let baseURL, !anonKey.isEmpty else { throw CoachError.notConfigured }
        let history = messages.filter { !$0.isLocal }.suffix(20).map { ["role": $0.role.rawValue, "content": $0.content] }
        let body: [String: Any] = ["messages": history, "context": personalization ? context : "", "personalization": personalization]
        let request = try await authorizedRequest(baseURL.appending(path: "functions/v1/coach"), body: body)
        let (data, response) = try await perform(request)
        switch response.statusCode {
        case 200:
            return try JSONDecoder().decode(CoachReply.self, from: data)
        case 401:
            keychain.delete("access_token")
            throw CoachError.server("Ta session a expiré. Réessaie.")
        case 429:
            let quota = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.quota
            throw CoachError.quotaReached(quota)
        default:
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
            throw CoachError.server(message ?? "Le Coach n'a pas pu répondre. Réessaie plus tard.")
        }
    }

    func deleteAccount() async throws {
        guard let baseURL, !anonKey.isEmpty, keychain.read("refresh_token") != nil else {
            clearSession()
            return
        }
        let request = try await authorizedRequest(baseURL.appending(path: "functions/v1/delete-account"), body: [:])
        let (_, response) = try await perform(request)
        guard response.statusCode == 200 || response.statusCode == 401 else {
            throw CoachError.server("La suppression du compte serveur a échoué. Réessaie plus tard.")
        }
        clearSession()
    }

    // MARK: - Session anonyme

    private struct SessionBody: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Double
    }

    private struct ErrorBody: Decodable {
        let error: String?
        let quota: CoachQuota?
    }

    private func authorizedRequest(_ url: URL, body: [String: Any]) async throws -> URLRequest {
        let token = try await accessToken()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func accessToken() async throws -> String {
        if let token = keychain.read("access_token"),
           let expiry = keychain.read("expires_at").flatMap(Double.init), Date().timeIntervalSince1970 < expiry - 60 {
            return token
        }
        if let refresh = keychain.read("refresh_token"),
           let renewed = try? await authenticate(path: "auth/v1/token", query: "grant_type=refresh_token", body: ["refresh_token": refresh]) {
            return renewed
        }
        // Première utilisation : création d'un compte anonyme, sans e-mail ni mot de passe.
        return try await authenticate(path: "auth/v1/signup", query: nil, body: [:])
    }

    private func authenticate(path: String, query: String?, body: [String: Any]) async throws -> String {
        guard let baseURL else { throw CoachError.notConfigured }
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.query = query
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await perform(request)
        guard response.statusCode == 200, let session = try? JSONDecoder().decode(SessionBody.self, from: data) else {
            throw CoachError.server("Connexion au Coach impossible pour le moment.")
        }
        keychain.write(session.access_token, for: "access_token")
        keychain.write(session.refresh_token, for: "refresh_token")
        keychain.write(String(Date().timeIntervalSince1970 + session.expires_in), for: "expires_at")
        return session.access_token
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw CoachError.network }
            return (data, http)
        } catch let error as CoachError {
            throw error
        } catch {
            throw CoachError.network
        }
    }

    private func clearSession() {
        ["access_token", "refresh_token", "expires_at"].forEach(keychain.delete)
    }
}

/// Réponses de démonstration, utilisées uniquement pour les aperçus et les captures d'écran automatiques.
/// Chaque réponse est explicitement marquée comme telle dans l'interface.
@MainActor
final class DemoCoachService: CoachServing {
    var isAvailable: Bool { true }

    func send(_ messages: [CoachMessage], context: String, personalization: Bool) async throws -> CoachReply {
        try? await Task.sleep(for: .milliseconds(400))
        return CoachReply(
            message: "Réponse de démonstration. Tu as indiqué dormir environ six heures par nuit. Viser au moins 7 heures, avec un horaire de coucher régulier, est bénéfique pour ton bien-être général [S:watson-2015-sleep]. En revanche, cela ne constitue pas un traitement démontré contre l'alopécie androgénétique. Si tu veux, on peut choisir ensemble une petite habitude du soir pour commencer.",
            citations: ["watson-2015-sleep"], safety: "none", quota: CoachQuota(used: 2, limit: 5, premium: false))
    }

    func deleteAccount() async throws {}
}

/// Stockage minimal dans le Trousseau iOS (jetons de session), accessible uniquement sur cet appareil.
struct KeychainStore {
    let service: String

    func read(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: key, kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ value: String, for key: String) {
        delete(key)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: key, kSecValueData as String: Data(value.utf8),
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemAdd(query as CFDictionary, nil)
    }

    func delete(_ key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
    }
}
