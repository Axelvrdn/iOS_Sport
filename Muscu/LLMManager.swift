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
        do {
            let model = try await MLXLMCommon.loadModel(directory: modelURL)
            chatSession = ChatSession(model)
            print("✅ Modèle chargé avec succès")
        } catch {
            print("❌ ERREUR Chargement: \(error)")
            // Si la configuration est corrompue (ex: config.json non‑JSON),
            // on nettoie entièrement le dossier modèle pour forcer un nouveau téléchargement propre.
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
        let fullPrompt = buildFullPrompt(prompt: prompt, systemPrompt: systemPrompt, context: context)
        do {
            return try await session.respond(to: fullPrompt)
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
        let fullPrompt = buildFullPrompt(prompt: prompt, systemPrompt: systemPrompt, context: context)
        print("🧠 Début de la génération pour le prompt: \(prompt)")
        var fullResponse = ""
        do {
            let response = try await session.respond(to: fullPrompt)
            fullResponse = response
            if response.isEmpty {
                print("⚠️ Réponse vide du modèle")
            }
            for char in response {
                let token = String(char)
                print("📝 Token reçu: \(token)")
                await onToken(token)
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
    }
}

enum LLMManagerError: Error {
    case modelFilesMissing
}
