//
//  AICoachViewModel.swift
//  Muscu
//
//  Cerveau IA Coach : generateResponse (System Prompt Elite), getUserContext (SwiftData → texte),
//  parser [ACTION: ..., VALUE: ...], typewriter, suggestedAction / suggestedProtocol pour "Click to Apply".
//  Préparé pour intégration modèle local (MLX / CoreML).
//

import Foundation
import SwiftData
import Observation

// MARK: - System Prompt Elite Athlete

private enum AICoachSystemPrompt {
    static let eliteAthlete = """
    Tu es un coach de performance de haut niveau, expert en biomécanique et physiologie. Ton ton est motivant, concis et "Elite".
    Règles strictes :
    - Blessures : Si l'utilisateur mentionne une douleur, active DIRECTEMENT le protocole de remplacement d'exercice. Ne propose jamais d'exercices risqués pour la zone concernée.
    - Progression : Tu analyses ses records (PRs) fournis dans le contexte. S'il stagne, suggère une semaine de Deload ou une augmentation de 2,5 kg sur l'exercice concerné.
    - Badges : Tu as le pouvoir d'attribuer des badges (ex. "Sagesse") si l'utilisateur accepte de se reposer ou d'appliquer un Deload — tu peux le mentionner pour renforcer la décision.
    - Modifications de poids ou planning : inclus en fin de réponse un flag machine-readable : [ACTION: UPDATE_WEIGHT, VALUE: +2.5] ou [ACTION: DELOAD] etc. Une seule action par message. Ne répète pas le flag dans le texte lisible.
    """
}

// MARK: - Parser des flags d'action (Click to Apply)

enum AICoachActionParser {
    /// Regex pour [ACTION: XXX, VALUE: YYY] ou [ACTION: XXX]. Retourne (texte sans flag, action, value).
    static func parse(_ rawReply: String) -> (displayText: String, action: String?, actionValue: String?) {
        let pattern = #"\[ACTION:\s*([^\],]+)(?:,\s*VALUE:\s*([^\]]+))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (rawReply, nil, nil)
        }
        let range = NSRange(rawReply.startIndex..., in: rawReply)
        var displayText = rawReply
        var action: String?
        var actionValue: String?

        if let match = regex.firstMatch(in: rawReply, range: range) {
            if let actionRange = Range(match.range(at: 1), in: rawReply) {
                action = String(rawReply[actionRange]).trimmingCharacters(in: .whitespaces)
            }
            if match.numberOfRanges > 2, let valueRange = Range(match.range(at: 2), in: rawReply) {
                actionValue = String(rawReply[valueRange]).trimmingCharacters(in: .whitespaces)
            }
            displayText = (rawReply as NSString).replacingCharacters(in: match.range, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (displayText, action, actionValue)
    }
}

@MainActor
@Observable
final class AICoachViewModel {

    let strictnessLevel: Double
    var activeProgram: TrainingProgram?
    var modelContext: ModelContext?
    /// Si false, seule la logique légère (règles) est utilisée ; le modèle lourd (MLX) n'est jamais chargé.
    var useLocalAIModel: Bool = false

    private(set) var messages: [AICoachMessage] = [
        AICoachMessage(text: "Salut, je suis ton coach IA. Comment tu te sens aujourd'hui ?", isUser: false, suggestedAction: nil, suggestedActionValue: nil, suggestedProtocol: nil)
    ]
    private(set) var typingMessageId: UUID?
    private(set) var currentTypingMessage: String = ""

    /// true pendant que l'IA réfléchit (chargement ou génération Mistral). Pour afficher une animation.
    private(set) var isProcessing: Bool = false

    /// 1 seconde d'indicateur "réflexion" puis écriture caractère par caractère.
    private let thinkingDuration: TimeInterval = 1.0
    private let typingIntervalPerCharacter: TimeInterval = 0.008

    init(strictnessLevel: Double) {
        self.strictnessLevel = strictnessLevel
    }

    // MARK: - Pipeline principal : génération de réponse

    /// Génère la réponse (moteur de règles uniquement). Utilisé quand useLocalAIModel == false.
    private func generateResponseRulesOnly(for prompt: String) -> (reply: String, suggestedAction: String?, suggestedActionValue: String?, suggestedProtocol: CoachProtocol?) {
        let contextString = getUserContext()
        let (rawReply, suggestedAction, suggestedProtocol) = processUserMessage(message: prompt, userContext: contextString)
        let (displayText, parsedAction, parsedValue) = AICoachActionParser.parse(rawReply)
        let finalAction = parsedAction ?? suggestedAction
        let finalValue = parsedAction != nil ? parsedValue : nil
        return (displayText, finalAction, finalValue, suggestedProtocol)
    }

    /// Envoie un message utilisateur. Si IA locale : génération Mistral async + streaming. Sinon : moteur de règles + typewriter.
    func submitMessage(_ userText: String) {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let userMsg = AICoachMessage(text: trimmed, isUser: true, suggestedAction: nil, suggestedActionValue: nil, suggestedProtocol: nil)
        messages.append(userMsg)

        if useLocalAIModel {
            Task { await submitMessageWithLocalAI(trimmed) }
        } else {
            let (reply, suggestedAction, suggestedActionValue, suggestedProtocol) = generateResponseRulesOnly(for: trimmed)
            let aiMessage = AICoachMessage(
                text: reply,
                isUser: false,
                suggestedAction: suggestedAction,
                suggestedActionValue: suggestedActionValue,
                suggestedProtocol: suggestedProtocol
            )
            messages.append(aiMessage)
            simulateTyping(for: reply, messageId: aiMessage.id)
        }
    }

    /// Génération réelle via Mistral (LLMManager) avec streaming. Fallback vers moteur de règles si timeout 5s sans réponse.
    private func submitMessageWithLocalAI(_ prompt: String) async {
        isProcessing = true
        let placeholderMessage = AICoachMessage(text: "", isUser: false, suggestedAction: nil, suggestedActionValue: nil, suggestedProtocol: nil)
        messages.append(placeholderMessage)
        typingMessageId = placeholderMessage.id
        currentTypingMessage = ""

        var fallbackUsed = false
        let contextString = getUserContext()

        let streamTask = Task {
            await LLMManager.shared.generateStreaming(
                prompt: prompt,
                systemPrompt: AICoachSystemPrompt.eliteAthlete,
                context: contextString,
                maxTokens: 500,
                temperature: 0.6
            ) { [weak self] token in
                guard let self else { return }
                self.currentTypingMessage += token
            }
        }

        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run {
                if self.currentTypingMessage.isEmpty && !fallbackUsed {
                    fallbackUsed = true
                    self.applyFallbackForLocalAI(prompt: prompt, placeholderMessage: placeholderMessage)
                }
            }
        }

        let fullReply = await streamTask.value
        _ = await timeoutTask.value

        if fallbackUsed {
            return
        }

        isProcessing = false
        typingMessageId = nil
        currentTypingMessage = ""

        let (displayText, parsedAction, parsedValue) = AICoachActionParser.parse(fullReply)
        if messages.last?.id == placeholderMessage.id {
            messages.removeLast()
        }
        let finalMessage = AICoachMessage(
            text: displayText.isEmpty ? "Je n'ai pas pu générer de réponse. Réessaie ou désactive l'IA locale." : displayText,
            isUser: false,
            suggestedAction: parsedAction,
            suggestedActionValue: parsedValue,
            suggestedProtocol: nil
        )
        messages.append(finalMessage)
    }

    /// Fallback : moteur de règles quand le modèle MLX ne répond pas (timeout ou erreur).
    private func applyFallbackForLocalAI(prompt: String, placeholderMessage: AICoachMessage) {
        isProcessing = false
        typingMessageId = nil
        currentTypingMessage = ""
        let (reply, suggestedAction, suggestedActionValue, suggestedProtocol) = generateResponseRulesOnly(for: prompt)
        if messages.last?.id == placeholderMessage.id {
            messages.removeLast()
        }
        let fallbackMessage = AICoachMessage(
            text: reply,
            isUser: false,
            suggestedAction: suggestedAction,
            suggestedActionValue: suggestedActionValue,
            suggestedProtocol: suggestedProtocol
        )
        messages.append(fallbackMessage)
    }

    // MARK: - Pipeline de données SwiftData → contexte texte pour l'IA

    /// Transforme les données SwiftData (Profil, séance du jour, records/PRs) en chaîne lisible par l'IA. Injecté au début de chaque "tour" de discussion.
    func getUserContext() -> String {
        guard let context = modelContext else { return "Contexte indisponible." }

        var sections: [String] = []

        // Profil
        let profileFetch = FetchDescriptor<UserProfile>()
        let profiles = (try? context.fetch(profileFetch)) ?? []
        if let profile = profiles.first {
            sections.append("""
            Profil: âge \(profile.age), poids \(profile.weight) kg, objectif physique \(profile.physiqueGoal.rawValue), \
            \(profile.sessionsPerWeek) séances/semaine, dernière séance \(formatDate(profile.lastWorkoutDate)), \
            durée dernière séance \(profile.lastWorkoutDurationSeconds)s, volume \(profile.lastWorkoutTotalVolumeKg) kg. \
            Niveau strictesse \(String(format: "%.2f", profile.strictnessLevel)). Zones sensibles: \(profile.injuredZonesJSON).
            """)
        } else {
            sections.append("Profil: non renseigné.")
        }

        // Séance du jour (première SessionRecipe du programme actif)
        if let program = activeProgram, let recipe = CoachProtocolApplier.firstSessionRecipe(in: program) {
            var sessionLines = ["Séance du jour: \(recipe.name), objectif \(recipe.goal.rawValue), focus \(recipe.bodyFocus.rawValue)."]
            for (idx, se) in recipe.exercises.enumerated() {
                let name = se.exercise?.name ?? "Exercice"
                let load = se.loadStrategy == .fixedWeight ? "\(se.loadValue) kg" : "\(se.loadValue)% 1RM"
                sessionLines.append("  \(idx + 1). \(name): \(se.sets)x\(se.reps), repos \(se.restTime)s, charge \(load).")
            }
            sections.append(sessionLines.joined(separator: "\n"))
        } else {
            sections.append("Séance du jour: aucun programme actif ou séance vide.")
        }

        // Records (PRs) — ExerciseSetResult par exercice, 1RM max
        let setResultFetch = FetchDescriptor<ExerciseSetResult>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let setResults = (try? context.fetch(setResultFetch)) ?? []
        var prByExercise: [String: (oneRM: Double, date: Date)] = [:]
        for r in setResults where r.estimatedOneRM > 0 {
            let key = r.exerciseName
            if let existing = prByExercise[key] {
                if r.estimatedOneRM > existing.oneRM {
                    prByExercise[key] = (r.estimatedOneRM, r.date)
                }
            } else {
                prByExercise[key] = (r.estimatedOneRM, r.date)
            }
        }
        if prByExercise.isEmpty {
            sections.append("Records (PRs): aucun enregistré.")
        } else {
            let prLines = prByExercise
                .sorted { $0.value.oneRM > $1.value.oneRM }
                .prefix(15)
                .map { "\($0.key): 1RM estimé \(String(format: "%.1f", $0.value.oneRM)) kg (\(formatDate($0.value.date)))" }
            sections.append("Records (PRs): " + prLines.joined(separator: "; "))
        }

        return sections.joined(separator: "\n\n")
    }

    private func formatDate(_ date: Date) -> String {
        if date == .distantPast || date.timeIntervalSince1970 < 1 { return "jamais" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    // MARK: - Réponses intelligentes (moteur de règles, utilisant le contexte)

    /// Analyse le message et retourne (réponse brute, action suggérée optionnelle, protocole suggéré optionnel).
    /// Peut inclure le flag [ACTION: ..., VALUE: ...] dans la réponse pour le parser.
    func processUserMessage(message: String, userContext: String = "") -> (reply: String, suggestedAction: String?, suggestedProtocol: CoachProtocol?) {
        let lowercased = message.lowercased()

        if lowercased.contains("nutrition") {
            return (nutritionReply(), nil, nil)
        }
        if lowercased.contains("analyser") || lowercased.contains("semaine") {
            return (analyserSemaineReply(userContext: userContext), nil, nil)
        }
        if lowercased.contains("optimiser") || lowercased.contains("poids") {
            return (optimiserPoidsReplyWithFlag(), "UPDATE_WEIGHT", nil)
        }
        if lowercased.contains("récupération") {
            return (recuperationReply(), nil, nil)
        }

        // Blessure / douleur : protocole immédiat, pas d'exercices risqués
        let mentionsPain = lowercased.contains("mal") || lowercased.contains("douleur") || lowercased.contains("blessure") || lowercased.contains("blessé") || lowercased.contains("douloureux")
        let zone = detectInjuryZone(lowercased)
        if mentionsPain {
            if let z = zone {
                return (injuryReplyWithZone(z), nil, .injury(zone: z))
            } else {
                return (injuryReplyAskZone(), nil, .injury(zone: nil))
            }
        }
        if zone != nil {
            return (injuryReplyWithZone(zone!), nil, .injury(zone: zone))
        }

        // Fatigué / repos : Deload + badge Sagesse possible
        let mentionsTired = lowercased.contains("fatigu") || lowercased.contains("tired") || lowercased.contains("épuisé") || lowercased.contains("crevé") || lowercased.contains("dur") || lowercased.contains("besoin de repos") || lowercased.contains("repos")
        if mentionsTired {
            return tiredOrRestReply()
        }

        return (defaultEncouragingReply(), nil, nil)
    }

    private func detectInjuryZone(_ text: String) -> BodyPart? {
        if text.contains("épaule") || text.contains("shoulder") { return .shoulder }
        if text.contains("genou") || text.contains("knee") { return .knee }
        if text.contains("dos") || text.contains("back") { return .back }
        if text.contains("poignet") || text.contains("wrist") { return .wrist }
        if text.contains("hanche") || text.contains("hip") { return .hip }
        if text.contains("cou") || text.contains("neck") { return .neck }
        if text.contains("cheville") || text.contains("ankle") { return .ankle }
        return nil
    }

    private func injuryReplyAskZone() -> String {
        tonePrefix() + "D’accord, on va adapter la séance pour protéger la zone concernée. Où as-tu mal ? (épaule, genou, dos, poignet, hanche, cou, cheville). Tu peux aussi appuyer sur « Appliquer le protocole Blessure » une fois la zone précisée." + toneSuffix()
    }

    private func injuryReplyWithZone(_ zone: BodyPart) -> String {
        let zoneName = zoneNameForPart(zone)
        if let program = activeProgram, let context = modelContext,
           let (fromName, toName) = CoachProtocolApplier.suggestedReplacementMessage(zone: zone, program: program, context: context) {
            return tonePrefix() + "J'ai vu que tu as mal à \(zoneName). On peut remplacer \(fromName) par \(toName) pour aujourd'hui. Tu veux appliquer ?" + toneSuffix()
        }
        return tonePrefix() + "On adapte la séance en évitant de charger \(zoneName). Tu peux appliquer le protocole Blessure pour remplacer les exercices concernés par des alternatives sûres." + toneSuffix()
    }

    private func zoneNameForPart(_ zone: BodyPart) -> String {
        switch zone {
        case .shoulder: return "l’épaule"
        case .knee: return "le genou"
        case .back: return "le dos"
        case .wrist: return "le poignet"
        case .hip: return "la hanche"
        case .neck: return "le cou"
        case .ankle: return "la cheville"
        }
    }

    private func tiredOrRestReply() -> (String, String?, CoachProtocol?) {
        return (tonePrefix() + "Tu as besoin de récupération. Je te suggère d'appliquer une semaine de Deload : on divise par 2 les séries et les reps de la séance en cours. Si tu acceptes de te reposer, je t'attribue le badge « Sagesse ». Tu pourras appliquer le protocole ci-dessous." + toneSuffix(), nil, .deload)
    }

    private func nutritionReply() -> String {
        let tips = [
            "Autour de l'entraînement : vise 20–30 g de protéines dans les 2 h après la séance pour favoriser la récupération musculaire.",
            "Hydratation : bois régulièrement avant, pendant et après. Une légère soif = tu es déjà en retard. Garde une bouteille à portée.",
            "Répartition : étale tes protéines sur la journée (petit-déj, déj, collation, dîner) plutôt qu’un gros repas unique pour une meilleure synthèse."
        ]
        return tonePrefix() + (tips.randomElement() ?? tips[0]) + toneSuffix()
    }

    private func analyserSemaineReply(userContext: String) -> String {
        let hasRecentPRs = userContext.contains("Records (PRs):") && !userContext.contains("aucun enregistré")
        let stagnation = hasRecentPRs && (userContext.contains("jamais") || userContext.contains("séance: aucun"))
        if stagnation {
            return tonePrefix() + "J'ai analysé tes données : tu stagnes. Je te suggère soit une semaine de Deload pour récupérer, soit une hausse de 2,5 kg sur ton prochain exercice prioritaire si tu te sens frais. Choisis en fonction de ta fatigue." + toneSuffix()
        }
        if hasRecentPRs {
            return tonePrefix() + "J'ai regardé tes derniers records : tu as des PRs en base. Continue comme ça, la régularité paie. Si tu valides toutes tes séries, on pourra viser +2,5 kg sur 1–2 mouvements la prochaine fois." + toneSuffix()
        }
        return tonePrefix() + "J'ai analysé ta semaine : volume et régularité sont là. Enregistre tes séries pour que je puisse suivre tes PRs ; ensuite on pourra viser une hausse de charge progressive." + toneSuffix()
    }


    private func optimiserPoidsReplyWithFlag() -> String {
        return tonePrefix() + "Pour optimiser tes poids : je te suggère d’augmenter la charge de 2,5 kg sur ton exercice le plus récent dès la prochaine séance si tu valides les séries prévues. Tu peux appliquer cette mise à jour en un tap. [ACTION: UPDATE_WEIGHT, VALUE: +2.5]" + toneSuffix()
    }

    private func recuperationReply() -> String {
        return tonePrefix() + "La récupération est clé. Sommeil, hydratation et alimentation soutiennent la progression. On peut aussi prévoir un jour de repos actif (marche, mobilité) si tu en ressens le besoin." + toneSuffix()
    }

    private func defaultEncouragingReply() -> String {
        return tonePrefix() + "Je prends en compte ton retour et j’ajuste la séance pour optimiser ta progression tout en gérant la récupération." + toneSuffix()
    }

    private func tonePrefix() -> String {
        if strictnessLevel < 0.33 { return "OK, on va y aller en douceur aujourd’hui. " }
        if strictnessLevel < 0.66 { return "Compris. On reste sérieux mais raisonnable. " }
        return "Pas d’excuses, mais on reste intelligents. "
    }

    private func toneSuffix() -> String {
        if strictnessLevel < 0.33 { return " Si la douleur augmente ou ne passe pas, on coupe court et on bascule sur du travail très léger ou du repos." }
        if strictnessLevel < 0.66 { return " On surveille les sensations pendant l’échauffement et on ajuste en temps réel." }
        return " Tu donnes tout sur ce qui est possible sans douleur, mais tu respectes strictement les consignes sur la zone fragile."
    }

    // MARK: - Typewriter (1 s thinking puis 0.03 s / caractère)

    func simulateTyping(for fullText: String, messageId: UUID) {
        typingMessageId = messageId
        currentTypingMessage = ""

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(thinkingDuration * 1_000_000_000))
            guard typingMessageId == messageId else { return }

            for char in fullText {
                guard typingMessageId == messageId else { break }
                currentTypingMessage.append(char)
                try? await Task.sleep(nanoseconds: UInt64(typingIntervalPerCharacter * 1_000_000_000))
            }
            typingMessageId = nil
        }
    }
}
