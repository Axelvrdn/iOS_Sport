import SwiftUI
import UIKit

private enum APIValidationState {
    case idle
    case validating
    case success
    case failure(String)
}

struct AICoachAPISettingsView: View {
    @State private var selectedProvider: LLMProvider = AISettingsManager.shared.loadProvider()
    @State private var apiKey: String = AISettingsManager.shared.loadAPIKey() ?? ""
    @State private var validationState: APIValidationState = .idle
    @State private var clipboardSuggestion: String?
    @State private var validationTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Fournisseur") {
                Picker("Fournisseur", selection: $selectedProvider) {
                    ForEach(LLMProvider.allCases) { provider in
                        Label(provider.rawValue,
                              systemImage: provider == .groq ? "bolt.fill" : "sparkles")
                            .tag(provider)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Clé API") {
                HStack {
                    SecureField("Collez votre clé API", text: $apiKey)
                        .textInputAutocapitalization(.none)
                        .autocorrectionDisabled(true)

                    Button {
                        handlePasteFromClipboard()
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderless)
                }

                if let suggestion = clipboardSuggestion {
                    HStack {
                        Text("Clé détectée dans le presse-papier.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Coller") {
                            apiKey = suggestion
                            clipboardSuggestion = nil
                        }
                        .font(.footnote.bold())
                    }
                }

                switch validationState {
                case .idle:
                    EmptyView()
                case .validating:
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Vérification de la clé…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                case .success:
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("Clé valide. Coach IA prêt.")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                case .failure(let message):
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("Accès rapides") {
                Link(destination: URL(string: "https://console.groq.com/keys")!) {
                    Label("Obtenir une clé Groq", systemImage: "bolt.fill")
                }
                Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                    Label("Obtenir une clé OpenAI", systemImage: "sparkles")
                }
                Link(destination: URL(string: "https://aistudio.google.com/")!) {
                    Label("Obtenir une clé Gemini", systemImage: "sparkles")
                }
            }

            Section("Aide") {
                Text("Groq propose actuellement un accès gratuit très généreux, idéal pour le développement. Vos crédits API sont gérés directement par votre fournisseur (Groq ou OpenAI). L’app ne facture aucun frais supplémentaire.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("API du Coach IA")
        .onAppear {
            inspectClipboard()
        }
        .onChange(of: apiKey) { _, newValue in
            // Validation silencieuse en temps réel (debounced)
            validationTask?.cancel()
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                validationState = .idle
                return
            }
            validationState = .validating
            validationTask = Task {
                // petit délai pour éviter de spammer pendant la frappe
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard !Task.isCancelled else { return }
                await validateAndSave(apiKey: trimmed, provider: selectedProvider)
            }
        }
        .onChange(of: selectedProvider) { _, _ in
            // Re-valider la clé avec le nouveau fournisseur
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            validationState = .validating
            validationTask?.cancel()
            validationTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                await validateAndSave(apiKey: trimmed, provider: selectedProvider)
            }
        }
    }

    // MARK: - Clipboard

    private func handlePasteFromClipboard() {
        if let str = UIPasteboard.general.string {
            apiKey = str.trimmingCharacters(in: .whitespacesAndNewlines)
            clipboardSuggestion = nil
        } else {
            clipboardSuggestion = nil
        }
    }

    private func inspectClipboard() {
        if let str = UIPasteboard.general.string {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("sk-") || trimmed.hasPrefix("gsk_") {
                clipboardSuggestion = trimmed
            }
        }
    }

    // MARK: - Validation

    @MainActor
    private func validateAndSave(apiKey: String, provider: LLMProvider) async {
        do {
            let ok = try await testAPIKey(apiKey: apiKey, provider: provider)
            if ok {
                AISettingsManager.shared.save(apiKey: apiKey, provider: provider)
                withAnimation {
                    validationState = .success
                }
            } else {
                validationState = .failure("Clé invalide ou accès refusé.")
            }
        } catch {
            validationState = .failure(error.localizedDescription)
        }
    }

    private func testAPIKey(apiKey: String, provider: LLMProvider) async throws -> Bool {
        let url: URL
        switch provider {
        case .openAI:
            url = URL(string: "https://api.openai.com/v1/models")!
        case .groq:
            url = URL(string: "https://api.groq.com/openai/v1/models")!
        case .gemini:
            url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)")!
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if provider == .gemini {
            // Clé passée dans l’URL pour Gemini.
        } else {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }
}

