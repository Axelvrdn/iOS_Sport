import Foundation

/// Message pour le backend LLM (différent du ChatMessage UI).
struct LLMChatMessage {
    let role: String   // "user" / "assistant" / "system"
    let content: String
}

/// Client HTTP pour le Coach IA (Groq par défaut, compatible OpenAI).
final class LLMService {
    static let shared = LLMService()
    private init() {}

    private enum LLMServiceError: Error {
        case missingAPIKey
        case httpStatus(Int)
        case rateLimited

        var userFacingMessage: String {
            switch self {
            case .rateLimited:
                return "Le coach est très sollicité en ce moment. Attends quelques secondes avant de renvoyer ton message."
            case .missingAPIKey:
                return "Clé API manquante."
            case .httpStatus:
                return "Erreur réseau."
            }
        }
    }

    // MARK: - Public

    /// Envoie un échange en streaming ; `onToken` est appelé au fur et à mesure.
    func sendStreaming(
        messages: [LLMChatMessage],
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        let provider = AISettingsManager.shared.loadProvider()
        // Retry/backoff uniquement sur 429.
        var backoffSeconds: UInt64 = 2
        for attempt in 0...1 {
            do {
                if provider == .gemini {
                    guard let geminiKey = AISettingsManager.shared.loadAPIKey(for: .gemini),
                          !geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw LLMServiceError.missingAPIKey
                    }
                    return try await sendStreamingGemini(messages: messages, apiKey: geminiKey, onToken: onToken)
                } else {
                    guard let key = AISettingsManager.shared.loadAPIKey(for: provider),
                          !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw LLMServiceError.missingAPIKey
                    }
                    return try await sendStreamingOpenAICompatible(messages: messages, apiKey: key, provider: provider, onToken: onToken)
                }
            } catch {
                // Si rate limited et provider Gemini, fallback → Groq (si clé dispo) pour CETTE requête.
                if isRateLimitError(error) {
                    if provider == .gemini {
                        if let groqKey = AISettingsManager.shared.loadAPIKey(for: .groq),
                           !groqKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return try await sendStreamingOpenAICompatible(messages: messages, apiKey: groqKey, provider: .groq, onToken: onToken)
                        }
                    }
                    // Retry une seule fois avec backoff exponentiel.
                    if attempt == 0 {
                        try? await Task.sleep(nanoseconds: backoffSeconds * 1_000_000_000)
                        backoffSeconds &*= 2
                        continue
                    }
                    throw LLMServiceError.rateLimited
                }
                throw error
            }
        }
        throw LLMServiceError.rateLimited
    }

    // MARK: - Private

    private func isRateLimitError(_ error: Error) -> Bool {
        if let e = error as? LLMServiceError, case .rateLimited = e { return true }
        let ns = error as NSError
        return ns.domain == "LLMService" && ns.code == 429
    }

    private func sendStreamingOpenAICompatible(
        messages: [LLMChatMessage],
        apiKey: String,
        provider: LLMProvider,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        let (url, model) = endpointAndModel(for: provider)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMServiceError.httpStatus(-1)
        }
        if http.statusCode == 429 {
            throw NSError(domain: "LLMService", code: 429, userInfo: [NSLocalizedDescriptionKey: "Rate limited"])
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMServiceError.httpStatus(http.statusCode)
        }

        var full = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let jsonPart = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            if jsonPart == "[DONE]" { break }

            guard let data = jsonPart.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let token = delta["content"] as? String else {
                continue
            }

            full += token
            onToken(token)
        }

        return full
    }

    /// Appel streaming pour Gemini (Google AI Studio) — format "contents".
    private func sendStreamingGemini(
        messages: [LLMChatMessage],
        apiKey: String,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:streamGenerateContent?key=\(apiKey)") else {
            throw NSError(domain: "LLMService", code: 3, userInfo: [NSLocalizedDescriptionKey: "URL Gemini invalide."])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Sépare le message système (personnalité) des messages utilisateur/assistant.
        let systemPrompt = messages.first(where: { $0.role == "system" })?.content
        let chatMessages = messages.filter { $0.role != "system" }

        // Gemini utilise "contents" avec {role, parts:[{text:"..."}]}.
        let contents: [[String: Any]] = chatMessages.map { msg in
            let role: String
            switch msg.role {
            case "assistant":
                role = "model"
            default:
                role = "user"
            }
            return [
                "role": role,
                "parts": [
                    ["text": msg.content]
                ]
            ]
        }

        var payload: [String: Any] = [
            "contents": contents
        ]

        // Pour Gemini, le prompt système passe par "system_instruction".
        if let systemPrompt {
            payload["system_instruction"] = [
                "parts": [
                    ["text": systemPrompt]
                ]
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMServiceError.httpStatus(-1)
        }
        if http.statusCode == 429 {
            throw NSError(domain: "LLMService", code: 429, userInfo: [NSLocalizedDescriptionKey: "Rate limited"])
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMServiceError.httpStatus(http.statusCode)
        }

        var full = ""
        for try await line in bytes.lines {
            let jsonPart = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if jsonPart.isEmpty { continue }
            if jsonPart == "[DONE]" { break }

            guard let data = jsonPart.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = obj["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let token = parts.first?["text"] as? String else {
                continue
            }

            full += token
            onToken(token)
        }

        return full
    }

    private func endpointAndModel(for provider: LLMProvider) -> (URL, String) {
        switch provider {
        case .groq:
            // Groq OpenAI-compatible endpoint
            return (URL(string: "https://api.groq.com/openai/v1/chat/completions")!, "llama-3.3-70b-versatile")
        case .openAI:
            return (URL(string: "https://api.openai.com/v1/chat/completions")!, "gpt-4.1-mini")
        case .gemini:
            // Le modèle est défini dans l'URL spécifique Gemini ; cette valeur n'est pas utilisée.
            return (URL(string: "https://generativelanguage.googleapis.com")!, "gemini-2.0-flash")
        }
    }
}

