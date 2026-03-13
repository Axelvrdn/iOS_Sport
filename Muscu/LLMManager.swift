//
//  LLMManager.swift
//  Muscu
//
//  Charge le modèle Mistral depuis Application Support/MistralModel et génère des réponses
//  via MLX (mlx-swift-lm). Configuration : mlx-community/Mistral-7B-Instruct-v0.3-4bit-mlx.
//  Chargement asynchrone pour ne pas figer l'interface ; génération avec GenerateParameters.
//

import Foundation
import MLX
import MLXNN
import MLXLLM
import MLXLMCommon
#if canImport(Darwin)
import Darwin
#endif

/// Gestionnaire du modèle local (Mistral 7B 4bit MLX). Charge depuis Application Support/MistralModel.
@MainActor
final class LLMManager {

    static let shared = LLMManager()

    /// Session de chat (modèle + tokenizer) une fois chargée.
    private var chatSession: ChatSession?

    /// Répertoire du modèle (Application Support/MistralModel).
    private static var modelDirectoryURL: URL {
        MistralModelStorage.directoryURL
    }

    private init() {}

    /// Vérifie que le modèle est prêt (fichiers présents dans MistralModel).
    static var isModelAvailable: Bool {
        ModelFiles.fileNames.allSatisfy { MistralModelStorage.hasFile($0) }
    }

    /// Charge le modèle et le tokenizer depuis Application Support/MistralModel.
    /// À appeler de manière asynchrone pour ne pas bloquer l'UI.
    func loadModel() async throws {
        try await setupLocalModel()
    }

    private func setupLocalModel() async throws {
        let modelURL = Self.modelDirectoryURL
        print("🛠 Tentative de chargement du modèle depuis: \(modelURL)")
        guard Self.isModelAvailable else {
            throw LLMManagerError.modelFilesMissing
        }

        // Libère autant que possible avant de charger le modèle lourd.
        URLCache.shared.removeAllCachedResponses()

        // Monitoring RAM avant / après chargement.
        Self.reportMemoryUsage(label: "avant chargement modèle")

        do {
            // Limite le cache GPU MLX à 1 Go pour éviter les pics au‑delà de 3 Go.
            MLX.GPU.set(cacheLimit: 1 * 1024 * 1024 * 1024)

            let model = try await MLXLMCommon.loadModel(directory: modelURL)

            autoreleasepool {
                // Réduit la durée de vie d'éventuels objets intermédiaires.
                chatSession = ChatSession(model)
            }

            // Libère le cache GPU après chargement.
            MLX.GPU.clearCache()

            print("✅ Modèle chargé avec succès")
            Self.reportMemoryUsage(label: "après chargement modèle")
        } catch {
            print("❌ ERREUR Chargement: \(error)")
            let description = String(describing: error)
            if description.contains("configurationDecodingError") || description.contains("config.json") {
                AIModelDownloader.clearModelFolder()
            }
            throw error
        }
    }

    /// Indique si le modèle est chargé en mémoire.
    var isLoaded: Bool {
        chatSession != nil
    }

    /// Génère une réponse. maxTokens: 500, temperature: 0.6 (équilibre expertise / motivation).
    func generate(prompt: String, systemPrompt: String, context: String) async -> String? {
        guard Self.isModelAvailable else { return nil }
        if !isLoaded {
            do {
                try await loadModel()
            } catch {
                print("[LLMManager] loadModel failed: \(error)")
                return nil
            }
        }
        guard let session = chatSession else { return nil }
        let trimmedContext = Self.truncatedContext(context, maxCharacters: 4096) // ~fenêtre réduite
        let fullPrompt = buildFullPrompt(prompt: prompt, systemPrompt: systemPrompt, context: trimmedContext)
        do {
            let response = try await session.respond(to: fullPrompt)
            MLX.GPU.clearCache()
            return response
        } catch {
            print("[LLMManager] generate failed: \(error)")
            return nil
        }
    }

    /// Génère en streaming : chaque segment est passé à `onToken` sur le MainActor (typewriter réactif).
    func generateStreaming(
        prompt: String,
        systemPrompt: String,
        context: String,
        maxTokens: Int = 500,
        temperature: Float = 0.6,
        onToken: @escaping @MainActor (String) -> Void
    ) async -> String {
        guard Self.isModelAvailable else { return "" }
        if !isLoaded {
            do {
                try await loadModel()
            } catch {
                print("[LLMManager] loadModel failed: \(error)")
                return ""
            }
        }
        guard let session = chatSession else { return "" }
        let trimmedContext = Self.truncatedContext(context, maxCharacters: 4096)
        let fullPrompt = buildFullPrompt(prompt: prompt, systemPrompt: systemPrompt, context: trimmedContext)
        print("🧠 Début de la génération pour le prompt: \(prompt)")
        var fullResponse = ""
        do {
            let response = try await session.respond(to: fullPrompt)
            fullResponse = response
            MLX.GPU.clearCache()
            if response.isEmpty {
                print("⚠️ Réponse vide du modèle")
            }
            for char in response {
                await onToken(String(char))
            }
            return fullResponse
        } catch {
            print("[LLMManager] generateStreaming failed: \(error)")
            return fullResponse
        }
    }

    private func buildFullPrompt(prompt: String, systemPrompt: String, context: String) -> String {
        """
        \(systemPrompt)

        --- Contexte utilisateur ---
        \(context)
        --- Fin contexte ---

        Utilisateur: \(prompt)
        Assistant:
        """
    }

    /// Décharge le modèle de la mémoire.
    func unloadModel() {
        chatSession = nil
        MLX.GPU.clearCache()
    }

    // MARK: - RAM Monitoring & Contexte

    /// Tronque le contexte pour limiter la taille effective de la fenêtre (RAM).
    private static func truncatedContext(_ context: String, maxCharacters: Int) -> String {
        guard context.count > maxCharacters else { return context }
        return String(context.suffix(maxCharacters))
    }

    /// Log la mémoire utilisée (resident size) avec un label.
    private static func reportMemoryUsage(label: String) {
        #if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / mach_msg_type_number_t(MemoryLayout<integer_t>.size)
        let kerr = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { machPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), machPtr, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / (1024 * 1024)
            print("📊 [RAM] (\(label)) Mémoire utilisée: \(String(format: "%.1f", usedMB)) MB")
        }
        #endif
    }
}

enum LLMManagerError: Error {
    case modelFilesMissing
}
