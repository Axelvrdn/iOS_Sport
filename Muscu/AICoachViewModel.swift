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
    - Modifications de poids ou planning : tu peux proposer des ajustements via des commandes machine-readable.
    - Tu NE DOIS PAS inventer de nouveaux exercices. Si un exercice n’est pas présent dans le programme du jour ou n’est pas mentionné explicitement par l’utilisateur, reste général (par ex. "travail de renforcement du bas du corps") ou demande une précision. Ne crée jamais de nom d’exercice de musculation qui n’existe pas dans le contexte.

    SYSTÈME DE COMMANDES (FORMAT JSON) :
    - Si tu veux signaler une blessure à ajouter, ajoute À LA FIN de ta réponse, sur une seule ligne, un bloc JSON précédé de "ACTION:" :
      ACTION: {"type": "ADD_INJURY", "part": "<partie_du_corps>"}
      Exemple : ACTION: {"type": "ADD_INJURY", "part": "genou"}
    - Si tu veux modifier le programme, ajoute :
      ACTION: {"type": "UPDATE_PROGRAM", "day": "<jour>", "exercises": ["Exercice 1", "Exercice 2", "..."]}

    Contraintes :
    - N'ajoute au maximum QU'UN seul bloc ACTION par réponse.
    - Ne mets JAMAIS ce JSON dans le texte lisible principal, uniquement à la fin. Le JSON doit être sur sa propre ligne, après ta réponse naturelle.
    - Réponds toujours en français impeccable, avec les bons accents (é, à, è, ô, ç, etc.).
    - Tes réponses doivent être concises et, autant que possible, structurées avec des listes à puces pour les consignes et programmes.
    """
}

// MARK: - Parser des flags d'action (Click to Apply)

enum AICoachActionParser {
    /// Parse un bloc JSON de commande précédé de "ACTION:".
    /// - Format attendu, en fin de réponse, sur sa propre ligne :
    ///   ACTION: {"type": "...", ...}
    /// - Retourne le texte nettoyé (sans la ligne ACTION) + le JSON brut en String.
    static func parse(_ rawReply: String) -> (displayText: String, action: String?, actionValue: String?) {
        var displayText = rawReply
        var actionJSON: String?

        // On inspecte la dernière ligne (ou les dernières lignes) pour trouver "ACTION:".
        let lines = rawReply.split(separator: "\n", omittingEmptySubsequences: false)
        var linesWithoutAction: [Substring] = []

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("ACTION:"),
               let range = line.range(of: "ACTION:") {
                let jsonPart = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if !jsonPart.isEmpty {
                    actionJSON = String(jsonPart)
                }
                // On n’ajoute pas cette ligne au displayText.
            } else {
                linesWithoutAction.append(line)
            }
        }

        displayText = linesWithoutAction.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (displayText, actionJSON, nil)
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

    // MARK: - Ajustement volume / mode Low-Power

    /// Ajuste le volume d'un programme atomique (TrainingProgram) selon le mode Low-Power et le nombre de jours cibles.
    /// - Parameters:
    ///   - program: Programme sur lequel appliquer l'ajustement.
    ///   - isLowPower: Si true, divise les séries / rounds par 2.
    ///   - targetDays: Ex: 6 (plein) ou 3 (pivot compressé A/B/C).
    func adjustVolume(for program: TrainingProgram, isLowPower: Bool, targetDays: Int) {
        guard let context = modelContext else { return }

        // 1) Réduction globale du volume (sets/rounds) si Low-Power.
        if isLowPower {
            for week in program.weeks {
                for day in week.days {
                    guard let recipe = day.sessionRecipe else { continue }
                    for se in recipe.exercises {
                        let currentSets = max(se.sets, 1)
                        se.sets = max(1, currentSets / 2)
                    }
                }
            }
        }

        // 2) Pivot 6 → 3 jours (A/B/C) pour Fighter Performance.
        if targetDays == 3 {
            pivotFighterPerformanceProgram(program)
        }

        do {
            try context.save()
        } catch {
            // En cas d'erreur de persistance, on ne fait rien (grâce optimiste).
        }
    }

    /// Fusionne les 6 jours Fighter Performance en 3 blocs A/B/C.
    private func pivotFighterPerformanceProgram(_ program: TrainingProgram) {
        guard let week = program.weeks.first else { return }

        let days = week.days

        func findDay(_ substring: String) -> TrainingDay? {
            days.first { $0.title.localizedCaseInsensitiveContains(substring) }
        }

        // Jour A : HIIT + Force
        if let hiitDay = findDay("HIIT Conditioning"),
           let forceDay = findDay("Force Explosive") {
            mergeDay(source: forceDay, into: hiitDay)
        }

        // Jour B : Shadow + Sparring
        if let shadowDay = findDay("Technique & Shadow"),
           let sparringDay = findDay("Sparring / Sac") {
            mergeDay(source: sparringDay, into: shadowDay)
        }

        // Jour C : Mobilité + Agilité
        if let mobilityDay = findDay("Mobilité & Hanches"),
           let agilityDay = findDay("Footwork & Agilité") {
            mergeDay(source: agilityDay, into: mobilityDay)
        }
    }

    /// Déplace tous les exercices SessionExercise de source vers target, puis marque source comme jour de repos.
    private func mergeDay(source: TrainingDay, into target: TrainingDay) {
        guard let sourceRecipe = source.sessionRecipe else { return }

        if target.sessionRecipe == nil {
            let newRecipe = SessionRecipe(
                name: target.title,
                goal: .volume,
                bodyFocus: .fullBody,
                sportCategoriesString: ""
            )
            newRecipe.day = target
            target.sessionRecipe = newRecipe
        }

        guard let targetRecipe = target.sessionRecipe else { return }

        for se in sourceRecipe.exercises {
            se.session = targetRecipe
            targetRecipe.exercises.append(se)
        }

        source.isRestDay = true
        source.title = "Repos (fusionné)"
        source.sessionRecipe = nil
    }

    // MARK: - Pipeline principal : génération de réponse

    /// Construit le prompt complet (contexte + message utilisateur) envoyé au LLM.
    func generateFullPrompt(for userMessage: String, context: String) -> String {
        return """
[CONTEXT_UTILISATEUR]
\(context)

[FIN_CONTEXT_UTILISATEUR]

[MESSAGE_UTILISATEUR]
\(userMessage)
[FIN_MESSAGE_UTILISATEUR]
"""
    }

    /// Envoie un message utilisateur. Si IA locale : génération Mistral async + streaming. Sinon : moteur de règles + typewriter.
    func submitMessage(_ userText: String) {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let userMsg = AICoachMessage(text: trimmed, isUser: true, suggestedAction: nil, suggestedActionValue: nil, suggestedProtocol: nil)
        messages.append(userMsg)

        // Si aucune API n'est configurée, on prévient l'utilisateur et on ne lance rien.
        guard AISettingsManager.shared.isConfigured else {
            let warning = AICoachMessage(
                text: "Configuration requise : ajoute une clé API Groq ou OpenAI dans les réglages pour discuter avec le coach.",
                isUser: false
            )
            messages.append(warning)
            return
        }

        print("🤖 IA en train de générer pour le prompt : \(trimmed)")
        Task { await submitMessageWithLocalAI(trimmed) }
    }

    /// Génération réelle via LLM distant (LLMService) avec streaming.
    private func submitMessageWithLocalAI(_ prompt: String) async {
        isProcessing = true
        let placeholderMessage = AICoachMessage(text: "", isUser: false, suggestedAction: nil, suggestedActionValue: nil, suggestedProtocol: nil)
        messages.append(placeholderMessage)
        typingMessageId = placeholderMessage.id
        currentTypingMessage = ""

        let contextString = getUserContext()

        let fullReply: String
        do {
            let useMinimalContext = shouldUseMinimalContext(for: prompt)
            let contextString = getUserContext(isMinimal: useMinimalContext)
            let fullPrompt = generateFullPrompt(for: prompt, context: contextString)
            let messagesPayload: [LLMChatMessage] = [
                LLMChatMessage(role: "system", content: AICoachSystemPrompt.eliteAthlete),
                LLMChatMessage(role: "user", content: fullPrompt)
            ]

            fullReply = try await LLMService.shared.sendStreaming(messages: messagesPayload) { [weak self] token in
                guard let self else { return }
                self.currentTypingMessage += token
            }
        } catch {
            isProcessing = false
            typingMessageId = nil
            currentTypingMessage = ""
            if messages.last?.id == placeholderMessage.id {
                messages.removeLast()
            }
            let ns = error as NSError
            let message: String
            if ns.domain == "LLMService" && ns.code == 429 {
                message = "Le coach est très sollicité en ce moment. Attends quelques secondes avant de renvoyer ton message."
            } else {
                message = "Le coach n’a pas pu répondre pour le moment. Vérifie ta connexion et réessaie."
            }
            let errMsg = AICoachMessage(text: message, isUser: false)
            messages.append(errMsg)
            return
        }

        isProcessing = false
        typingMessageId = nil
        currentTypingMessage = ""

        let (displayText, parsedAction, parsedValue) = AICoachActionParser.parse(fullReply)
        if messages.last?.id == placeholderMessage.id {
            messages.removeLast()
        }
        let finalText = displayText.isEmpty
            ? "Je n'ai pas pu générer de réponse pour le moment. Réessaie dans quelques secondes."
            : displayText
        let finalMessage = AICoachMessage(
            text: finalText,
            isUser: false,
            suggestedAction: parsedAction,
            suggestedActionValue: parsedValue,
            suggestedProtocol: nil
        )
        messages.append(finalMessage)
    }

    // MARK: - Pipeline de données SwiftData → contexte texte pour l'IA

    /// Transforme les données SwiftData (Profil, séance du jour, records/PRs) en chaîne lisible par l'IA. Injecté au début de chaque "tour" de discussion.
    func getUserContext(isMinimal: Bool = false) -> String {
        guard let context = modelContext else { return "Contexte indisponible." }

        var sections: [String] = []

        // Profil minimal
        let profileFetch = FetchDescriptor<UserProfile>()
        let profiles = (try? context.fetch(profileFetch)) ?? []
        if let profile = profiles.first {
            let plannedSessionsPerWeek = profile.disciplineSchedule.values.reduce(0) { $0 + $1.count }
            sections.append("""
Profil: âge \(profile.age), poids \(profile.weight) kg, objectif physique \(profile.physiqueGoal.rawValue), \(plannedSessionsPerWeek) séances planifiées/semaine, dernière séance \(formatDate(profile.lastWorkoutDate)), durée dernière séance \(profile.lastWorkoutDurationSeconds)s, volume \(profile.lastWorkoutTotalVolumeKg) kg. Niveau strictesse \(String(format: "%.2f", profile.strictnessLevel)). Zones sensibles: \(profile.injuredZonesJSON).
""")
        } else {
            sections.append("Profil: non renseigné.")
        }

        // Séance du jour (première SessionRecipe du programme actif)
        if let program = activeProgram, let recipe = CoachProtocolApplier.firstSessionRecipe(in: program) {
            if isMinimal {
                sections.append("Séance du jour: \(recipe.name), objectif \(recipe.goal.rawValue), focus \(recipe.bodyFocus.rawValue).")
            } else {
                var sessionLines = ["Séance du jour: \(recipe.name), objectif \(recipe.goal.rawValue), focus \(recipe.bodyFocus.rawValue)."]
                for (idx, se) in recipe.exercises.enumerated() {
                    let name = se.exercise?.name ?? "Exercice"
                    let load = se.loadStrategy == .fixedWeight ? "\(se.loadValue) kg" : "\(se.loadValue)% 1RM"
                    sessionLines.append("  \(idx + 1). \(name): \(se.sets)x\(se.reps), repos \(se.restTime)s, charge \(load).")
                }
                sections.append(sessionLines.joined(separator: "\n"))
            }
        } else {
            sections.append("Séance du jour: aucun programme actif ou séance vide.")
        }

        if isMinimal {
            sections.append("Records (PRs): non fournis pour économiser les tokens. Si nécessaire, demande-moi.")
            sections.append("Bibliothèque d'exercices: disponible côté app. Si tu as besoin de suggérer un nouvel exercice, demande une précision.")
            return sections.joined(separator: "\n\n")
        }

        // Records (PRs) — uniquement les 5 derniers PRs significatifs.
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
                .prefix(5)
                .map { "\($0.key): 1RM estimé \(String(format: "%.1f", $0.value.oneRM)) kg (\(formatDate($0.value.date)))" }
            sections.append("Records (PRs): " + prLines.joined(separator: "; "))
        }

        // Indication sur la bibliothèque d'exercices sans lister les 172 entrées.
        sections.append("Bibliothèque d'exercices: disponible côté app. Si tu as besoin de suggérer un nouvel exercice, reste général (par exemple « renforcement bas du corps ») ou demande une précision à l'utilisateur. Ne crée pas de nouveaux noms d'exercices.")

        return sections.joined(separator: "\n\n")
    }

    private func shouldUseMinimalContext(for userMessage: String) -> Bool {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count <= 12 else { return false }
        let smallTalk = ["salut", "hello", "yo", "coucou", "hey", "bonjour", "bonsoir", "ça va", "cv"]
        return smallTalk.contains { trimmed.contains($0) }
    }

    // MARK: - Adaptation automatique des programmes à partir du profil

    /// Adapte un programme à l'utilisateur courant (No Gym, etc.).
    func adaptProgramForCurrentUser(_ program: TrainingProgram) {
        guard let context = modelContext else { return }
        let profiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        guard let profile = profiles.first else { return }

        if !profile.hasGymAccess {
            applyNoGymVariants(to: program)
        }
    }

    /// Masque / remplace les exercices nécessitant une salle par des variantes poids du corps.
    private func applyNoGymVariants(to program: TrainingProgram) {
        guard let context = modelContext else { return }

        let masters = (try? context.fetch(FetchDescriptor<ExerciseMaster>())) ?? []
        let byName = Dictionary(uniqueKeysWithValues: masters.map { ($0.name, $0) })

        // Mapping manuel des variantes No Gym.
        let bodyweightFallbacks: [String: String] = [
            "Back squat": "Goblet Squat",
            "Trap Bar Deadlift": "Soulevé de terre jambes tendues",
            "Développé militaire": "Pompes explosives",
            "Face-Pulls": "Oiseau haltères",
            "Farmer's Walk": "Carry Valise"
        ]

        for week in program.weeks {
            for day in week.days {
                guard let recipe = day.sessionRecipe else { continue }

                for se in recipe.exercises {
                    guard let master = se.exercise else { continue }
                    // Si une variante No‑Gym est définie pour cet exercice, on la remplace.
                    if let fallbackName = bodyweightFallbacks[master.name],
                       let fallbackMaster = byName[fallbackName] {
                        se.exercise = fallbackMaster
                    }
                }
            }
        }
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
