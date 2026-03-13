import Foundation
import Security
import Observation

enum LLMProvider: String, CaseIterable, Identifiable {
    case groq = "Groq"
    case openAI = "OpenAI"
    case gemini = "Gemini"

    var id: String { rawValue }
}

/// Gestion centralisée et sécurisée des réglages IA (clé API, fournisseur).
@Observable
final class AISettingsManager {
    static let shared = AISettingsManager()

    private init() {
        refreshConfiguredFlag()
    }

    private let service = "com.muscu.ai.settings"
    private let apiKeyAccount = "ai_api_key"
    private let providerAccount = "ai_provider"

    // MARK: - État réactif

    /// true si une clé API non vide est présente dans le Keychain.
    var isConfigured: Bool = false

    // MARK: - API publique

    func save(apiKey: String, provider: LLMProvider) {
        // Backward compatible: sauvegarde "globale" (clé courante) + clé spécifique par provider (pour fallback).
        saveToKeychain(value: apiKey, account: apiKeyAccount)
        saveToKeychain(value: apiKey, account: apiKeyAccount(for: provider))
        saveToKeychain(value: provider.rawValue, account: providerAccount)
        refreshConfiguredFlag()
    }

    func loadAPIKey() -> String? {
        let provider = loadProvider()
        return loadAPIKey(for: provider)
    }

    /// Clé API spécifique à un provider (utile pour fallback Gemini → Groq).
    func loadAPIKey(for provider: LLMProvider) -> String? {
        // Priorité: clé spécifique provider, sinon legacy clé globale.
        if let key = loadFromKeychain(account: apiKeyAccount(for: provider)),
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key
        }
        return loadFromKeychain(account: apiKeyAccount)
    }

    func loadProvider() -> LLMProvider {
        if let raw = loadFromKeychain(account: providerAccount),
           let provider = LLMProvider(rawValue: raw) {
            return provider
        }
        // Par défaut on privilégie Groq (free tier généreux).
        return .groq
    }

    // MARK: - Helpers Keychain / état

    private func refreshConfiguredFlag() {
        if let key = loadAPIKey() {
            isConfigured = !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            isConfigured = false
        }
    }

    private func apiKeyAccount(for provider: LLMProvider) -> String {
        switch provider {
        case .groq: return "ai_api_key_groq"
        case .openAI: return "ai_api_key_openai"
        case .gemini: return "ai_api_key_gemini"
        }
    }

    private func saveToKeychain(value: String, account: String) {
        let data = Data(value.utf8)

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // Supprime l’entrée existante si elle existe.
        SecItemDelete(baseQuery as CFDictionary)

        var attributes = baseQuery
        attributes[kSecValueData as String] = data

        SecItemAdd(attributes as CFDictionary, nil)
    }

    private func loadFromKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
}

