//
//  AICoachView.swift
//  Muscu
//
//  DA "Elite Architect" : interface AI Coach futuriste, onde animée, bulles glassmorphism, typewriter, thinking.
//  Utilisé par : WorkoutView (sheet), éventuellement Paramètres.
//

import SwiftUI
import SwiftData
import UIKit

private let AICoachBgDark = Color(red: 15/255, green: 17/255, blue: 21/255)   // #0F1115
private let AICoachCardDark = Color(red: 28/255, green: 31/255, blue: 38/255)  // #1C1F26
/// Bordure bleu clair pour les cartes protocole Repos / Deload.
private let protocolRestColor = Color(red: 0.45, green: 0.7, blue: 1)

// MARK: - Message modèle (réutilisable)

struct AICoachMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    /// Ex. "UPDATE_WEIGHT" pour afficher le bouton "Appliquer la suggestion".
    var suggestedAction: String?
    /// Valeur associée à l'action (ex: "+2.5" pour UPDATE_WEIGHT) — parsée depuis le flag [ACTION: ..., VALUE: ...].
    var suggestedActionValue: String?
    /// Protocole de santé suggéré (blessure, deload, repos total) pour afficher la carte et le bouton "Appliquer".
    var suggestedProtocol: CoachProtocol?

    init(text: String, isUser: Bool, suggestedAction: String? = nil, suggestedActionValue: String? = nil, suggestedProtocol: CoachProtocol? = nil) {
        self.text = text
        self.isUser = isUser
        self.suggestedAction = suggestedAction
        self.suggestedActionValue = suggestedActionValue
        self.suggestedProtocol = suggestedProtocol
    }
}

// MARK: - Indicateur de réflexion (trois points désynchronisés)

private struct ThinkingDotsView: View {
    let color: Color
    @State private var phase1: CGFloat = 0
    @State private var phase2: CGFloat = 0
    @State private var phase3: CGFloat = 0

    var body: some View {
        HStack(spacing: 6) {
            dot(phase: phase1)
            dot(phase: phase2)
            dot(phase: phase3)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { phase1 = 1 }
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(0.15)) { phase2 = 1 }
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(0.3)) { phase3 = 1 }
        }
    }

    private func dot(phase: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .offset(y: 4 - phase * 8)
    }
}

// MARK: - Pastille pulsante (respiration)

private struct PulsingDotView: View {
    let color: Color
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .scaleEffect(isPulsing ? 1.3 : 0.85)
            .opacity(isPulsing ? 0.9 : 0.5)
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

// MARK: - Onde sinusoïdale animée

private struct WaveformShape: Shape {
    var phase: CGFloat
    var amplitude: CGFloat
    var frequency: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let width = rect.width
        path.move(to: CGPoint(x: 0, y: midY))
        for x in stride(from: 0, through: width, by: 2) {
            let relativeX = x / width
            let y = midY + sin(relativeX * .pi * frequency + phase) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: width, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct WaveformView: View {
    let accentColor: Color
    let colorScheme: ColorScheme
    @State private var phase: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.03)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            WaveformShape(phase: CGFloat(t * 2), amplitude: 12, frequency: 4)
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(colorScheme == .dark ? 0.5 : 0.7),
                            accentColor.opacity(0.15),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .glow(color: accentColor, opacity: colorScheme == .dark ? 0.4 : 0.5, radius: 16, y: 8)
        }
        .frame(height: 80)
    }
}

// MARK: - Vue principale AI Coach

/// Clé AppStorage pour activer/désactiver la synthèse vocale du coach.
let isAICoachVoiceEnabledKey = "isAICoachVoiceEnabled"
/// Clé AppStorage pour activer l'IA locale (modèle lourd type MLX). Nécessite 8 Go RAM (iPhone 15 Pro / M1+).
let localAIEnabledKey = "localAIEnabled"

struct AICoachView: View {
    let strictnessLevel: Double
    var activeProgram: TrainingProgram?

    @AppStorage(isAICoachVoiceEnabledKey) private var isVoiceEnabled: Bool = false
    @AppStorage(localAIEnabledKey) private var localAIEnabled: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentColor) private var accentColor
    @Environment(\.textOnAccentColor) private var textOnAccentColor
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel: AICoachViewModel
    @State private var speechManager = AICoachSpeechManager()
    @State private var inputText: String = ""
    @State private var typingGlowOpacity: Double = 0.2
    @State private var weightUpdateConfirmationMessageId: UUID?
    @State private var protocolAppliedMessageId: UUID?
    @State private var injuryZonePickerMessageId: UUID?
    /// Rate-limit haptic : max 20/s (intervalle minimum 0,05 s).
    @State private var lastHapticTime: Date = .distantPast
    @State private var hapticGenerator: UIImpactFeedbackGenerator?

    init(strictnessLevel: Double, activeProgram: TrainingProgram? = nil) {
        self.strictnessLevel = strictnessLevel
        self.activeProgram = activeProgram
        _viewModel = State(initialValue: AICoachViewModel(strictnessLevel: strictnessLevel))
    }

    private var pageBackground: Color {
        colorScheme == .dark ? AICoachBgDark : Color.white
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                pageBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header discret + pastille pulsante
                    headerView
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    // Messages
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                ForEach(viewModel.messages) { message in
                                    messageRow(message)
                                        .id(message.id)
                                }
                                Color.clear
                                    .frame(height: 1)
                                    .id("bottom")
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                        }
                        .safeAreaPadding(.bottom, 120)
                        .scrollDismissesKeyboard(.interactively)
                        .onAppear {
                            if hapticGenerator == nil {
                                hapticGenerator = UIImpactFeedbackGenerator(style: .soft)
                            }
                        }
                        .onChange(of: viewModel.messages.count) { _, _ in
                            scrollToBottom(proxy: proxy)
                        }
                        .onChange(of: viewModel.typingMessageId) { _, newId in
                            if newId != nil {
                                hapticGenerator?.prepare()
                            }
                        }
                        .onChange(of: viewModel.currentTypingMessage) { _, newText in
                            if viewModel.typingMessageId != nil {
                                // Haptic limité à 20 Hz : uniquement sur les espaces (entre les mots) pour éviter le rate-limit 32 Hz.
                                let now = Date()
                                if newText.last == " " && now.timeIntervalSince(lastHapticTime) > 0.05 {
                                    lastHapticTime = now
                                    hapticGenerator?.impactOccurred(intensity: 0.3)
                                }
                                scrollToBottom(proxy: proxy)
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }

                // Onde en bas (au-dessus de l'input)
                VStack {
                    Spacer()
                    WaveformView(accentColor: accentColor, colorScheme: colorScheme)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                }
                .allowsHitTesting(false)

                // Zone input + quick actions
                VStack(spacing: 12) {
                    quickActionsRow
                    inputRow
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .padding(.top, 12)
                .background(
                    LinearGradient(
                        colors: [pageBackground.opacity(0.7), pageBackground],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .onAppear {
                viewModel.activeProgram = activeProgram
                viewModel.modelContext = modelContext
                viewModel.useLocalAIModel = localAIEnabled && HardwareManager.isLocalAISupported
                if localAIEnabled && HardwareManager.isLocalAISupported && LLMManager.isModelAvailable {
                    Task { try? await LLMManager.shared.loadModel() }
                }
            }
            .onChange(of: activeProgram) { _, newProgram in
                viewModel.activeProgram = newProgram
            }
            .onChange(of: localAIEnabled) { _, enabled in
                viewModel.useLocalAIModel = enabled && HardwareManager.isLocalAISupported
                if enabled && HardwareManager.isLocalAISupported && LLMManager.isModelAvailable {
                    Task { try? await LLMManager.shared.loadModel() }
                }
            }
            .navigationTitle("AI Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isVoiceEnabled.toggle()
                        if !isVoiceEnabled { speechManager.stop() }
                    } label: {
                        Image(systemName: isVoiceEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(isVoiceEnabled ? accentColor : Color.secondary)
                            .symbolRenderingMode(isVoiceEnabled ? .hierarchical : .monochrome)
                            .glow(color: accentColor, opacity: isVoiceEnabled ? (colorScheme == .dark ? 0.5 : 0.35) : 0, radius: isVoiceEnabled ? 12 : 0, y: 4)
                    }
                    .accessibilityLabel(isVoiceEnabled ? "Désactiver la voix" : "Activer la voix")
                }
            }
            .onChange(of: viewModel.typingMessageId) { previousId, newId in
                if previousId != nil && newId == nil && isVoiceEnabled,
                   let completedId = previousId,
                   let msg = viewModel.messages.first(where: { $0.id == completedId }),
                   !msg.isUser, !msg.text.isEmpty {
                    speechManager.speak(msg.text)
                }
            }
            .onDisappear { speechManager.stop() }
            .sheet(isPresented: Binding(
                get: { injuryZonePickerMessageId != nil },
                set: { if !$0 { injuryZonePickerMessageId = nil } }
            )) {
                if let messageId = injuryZonePickerMessageId {
                    injuryZonePickerSheet(messageId: messageId)
                }
            }
        }
    }

    private func injuryZonePickerSheet(messageId: UUID) -> some View {
        let zones: [(BodyPart, String)] = [(.back, "Dos"), (.shoulder, "Épaule"), (.knee, "Genou")]
        return NavigationStack {
            List {
                ForEach(zones, id: \.0.rawValue) { pair in
                    Button {
                        applyProtocolAndConfirm(.injury(zone: nil), messageId: messageId, zone: pair.0)
                    } label: {
                        HStack {
                            Text(pair.1)
                                .foregroundStyle(Color.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Zone concernée")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.medium])
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private var headerView: some View {
        HStack(spacing: 10) {
            Text("AI COACH")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Color.secondary)
            if viewModel.isProcessing {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(accentColor)
            } else {
                PulsingDotView(color: accentColor)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func messageRow(_ message: AICoachMessage) -> some View {
        let showApplyButton = !message.isUser
            && message.suggestedAction == "UPDATE_WEIGHT"
            && message.id != viewModel.typingMessageId
        let showWeightConfirmation = weightUpdateConfirmationMessageId == message.id
        let showProtocolCard = !message.isUser
            && message.suggestedProtocol != nil
            && message.id != viewModel.typingMessageId
        let showProtocolConfirmation = protocolAppliedMessageId == message.id

        return HStack(alignment: .bottom, spacing: 0) {
            if message.isUser { Spacer(minLength: 60) }
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                messageBubble(message)
                    .frame(maxWidth: 280, alignment: message.isUser ? .trailing : .leading)
                if showApplyButton {
                    if showWeightConfirmation {
                        Text("Poids mis à jour !")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    } else {
                        applyWeightUpdateButton(message: message, messageId: message.id)
                    }
                }
                if showProtocolCard {
                    if showProtocolConfirmation {
                        Text("Protocole appliqué.")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    } else if let protocolKind = message.suggestedProtocol {
                        let count = CoachProtocolApplier.previewModificationCount(protocol: protocolKind, program: activeProgram, context: modelContext)
                        protocolCard(protocolKind, messageId: message.id, modificationCount: count)
                    }
                }
            }
            .frame(maxWidth: 280, alignment: message.isUser ? .trailing : .leading)
            if !message.isUser { Spacer(minLength: 60) }
        }
    }

    private func protocolCard(_ protocolKind: CoachProtocol, messageId: UUID, modificationCount: Int?) -> some View {
        let (borderColor, title, subtitle) = protocolCardContent(protocolKind, modificationCount: modificationCount)
        let isInjury = isInjuryProtocol(protocolKind)
        return VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Color.secondary)
            Button {
                if isInjury {
                    injuryZonePickerMessageId = messageId
                } else {
                    applyProtocolAndConfirm(protocolKind, messageId: messageId)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isInjury ? "shield.fill" : "moon.zzz.fill")
                        .font(.system(size: 16))
                    Text(protocolButtonLabel(protocolKind))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(accentColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accentColor.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(accentColor, lineWidth: 2))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.05))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(borderColor, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func isInjuryProtocol(_ p: CoachProtocol) -> Bool {
        if case .injury = p { return true }
        return false
    }

    private func protocolCardContent(_ p: CoachProtocol, modificationCount: Int?) -> (borderColor: Color, title: String, subtitle: String) {
        switch p {
        case .injury:
            let n = modificationCount ?? 0
            let sub = n > 0 ? "Modifier \(n) exercice\(n > 1 ? "s" : "") ?" : "Remplacer les exercices de la zone par des alternatives sûres. Appliquer ?"
            return (Color.orange, "Le coach suggère : Protocole Blessure", sub)
        case .deload:
            let n = modificationCount ?? 0
            let sub = n > 0 ? "Passer en mode Récupération. Modifier \(n) exercice\(n > 1 ? "s" : "") ?" : "Réduire de 50 % le volume de la séance active. Modifier les exercices ?"
            return (protocolRestColor, "Le coach suggère : Passer en mode Récupération", sub)
        case .fullRest:
            return (protocolRestColor, "Le coach suggère : Repos total", "Insérer 7 jours de repos dans le programme. Continuer ?")
        }
    }

    private func protocolButtonLabel(_ p: CoachProtocol) -> String {
        switch p {
        case .injury: return "Appliquer Protocole Blessure"
        case .deload: return "Appliquer une semaine de Deload"
        case .fullRest: return "Semaine de Repos"
        }
    }

    private func applyProtocolAndConfirm(_ protocolKind: CoachProtocol, messageId: UUID, zone: BodyPart? = nil) {
        guard let program = activeProgram else { return }
        do {
            switch protocolKind {
            case .deload:
                _ = try CoachProtocolApplier.applyDeload(program: program, context: modelContext)
            case .fullRest:
                try CoachProtocolApplier.applyFullRest(program: program, context: modelContext)
            case .injury:
                _ = try CoachProtocolApplier.applyInjury(zone: zone, program: program, context: modelContext)
            }
            protocolAppliedMessageId = messageId
            injuryZonePickerMessageId = nil
        } catch {
            injuryZonePickerMessageId = nil
        }
    }

    private func applyWeightUpdateButton(message: AICoachMessage, messageId: UUID) -> some View {
        let buttonLabel: String = {
            if let value = message.suggestedActionValue, !value.isEmpty {
                return "Appliquer la suggestion (\(value))"
            }
            return "Appliquer la suggestion"
        }()
        return Button {
            applyWeightUpdateAndConfirm(message: message, messageId: messageId)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 14))
                Text(buttonLabel)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
            .foregroundStyle(textOnAccentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(accentColor.opacity(0.85))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func applyWeightUpdateAndConfirm(message: AICoachMessage, messageId: UUID) {
        guard let lastExercise = findLastSessionExerciseInActiveProgram() else { return }
        let delta = parseWeightDelta(from: message.suggestedActionValue) ?? 2.5
        lastExercise.loadValue += delta
        do {
            try modelContext.save()
            weightUpdateConfirmationMessageId = messageId
        } catch {
            // Silently fail; could show an alert
        }
    }

    /// Parse VALUE du flag (ex: "+2.5", "-1") en Double pour la mise à jour de charge.
    private func parseWeightDelta(from value: String?) -> Double? {
        guard let s = value?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        let cleaned = s.replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }

    /// Dernier exercice (par ordre) de la première séance du programme actif.
    private func findLastSessionExerciseInActiveProgram() -> SessionExercise? {
        guard let program = activeProgram else { return nil }
        for week in program.weeks {
            for day in week.days {
                if let recipe = day.sessionRecipe, let last = recipe.exercises.last {
                    return last
                }
            }
        }
        return nil
    }

    private func messageBubble(_ message: AICoachMessage) -> some View {
        let isTypingThis = !message.isUser && message.id == viewModel.typingMessageId
        let showThinking = isTypingThis && viewModel.currentTypingMessage.isEmpty
        let displayText = isTypingThis ? viewModel.currentTypingMessage : message.text

        let shape = message.isUser
            ? UnevenRoundedRectangle(cornerRadii: .init(topLeading: 20, bottomLeading: 20, bottomTrailing: 6, topTrailing: 6), style: .continuous)
            : UnevenRoundedRectangle(cornerRadii: .init(topLeading: 6, bottomLeading: 6, bottomTrailing: 20, topTrailing: 20), style: .continuous)

        return Group {
            if showThinking {
                ThinkingDotsView(color: Color.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            } else {
                Text(displayText)
                    .font(.subheadline)
                    .foregroundStyle(message.isUser ? textOnAccentColor : Color.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .background {
            if message.isUser {
                shape.fill(accentColor)
            } else {
                shape.fill(.ultraThinMaterial)
            }
        }
        .overlay(shape.strokeBorder(message.isUser ? Color.clear : Color.primary.opacity(0.08), lineWidth: 0.5))
        .overlay {
            if isTypingThis && !showThinking {
                shape.strokeBorder(accentColor.opacity(typingGlowOpacity), lineWidth: 1)
                .allowsHitTesting(false)
            }
        }
        .clipShape(shape)
        .shadow(color: Color.black.opacity(colorScheme == .light && !message.isUser ? 0.06 : 0), radius: 8, x: 0, y: 2)
    }

    private var quickActionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                quickActionButton("Analyser ma semaine")
                quickActionButton("Conseil nutrition")
                quickActionButton("Optimiser mes poids")
                quickActionButton("Récupération")
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 44)
    }

    private func quickActionButton(_ title: String) -> some View {
        Button {
            sendQuickAction(title)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(accentColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.clear)
                .overlay(Capsule().strokeBorder(accentColor, lineWidth: 0.5))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var inputRow: some View {
        HStack(spacing: 10) {
            TextField("Dis au coach…", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .lineLimit(1...4)

            Button {
                sendMessage()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(textOnAccentColor)
                    .frame(width: 44, height: 44)
                    .background(accentColor)
                    .clipShape(Circle())
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = ""
        viewModel.submitMessage(trimmed)
        startGlowPulseWhenTyping()
    }

    private func sendQuickAction(_ action: String) {
        viewModel.submitMessage(action)
        startGlowPulseWhenTyping()
    }

    private func startGlowPulseWhenTyping() {
        typingGlowOpacity = 0.2
        Task { @MainActor in
            while viewModel.typingMessageId != nil {
                withAnimation(.easeInOut(duration: 0.7)) { typingGlowOpacity = 0.5 }
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard viewModel.typingMessageId != nil else { break }
                withAnimation(.easeInOut(duration: 0.7)) { typingGlowOpacity = 0.2 }
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }
    }
}

#Preview("AI Coach") {
    AICoachView(strictnessLevel: 0.7)
        .environment(\.accentColor, Color(red: 208/255, green: 253/255, blue: 62/255))
        .environment(\.textOnAccentColor, Color(red: 15/255, green: 17/255, blue: 21/255))
}
