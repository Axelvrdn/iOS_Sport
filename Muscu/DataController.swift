//
//  DataController.swift
//  Muscu
//
//  Rôle : Seeding (createDefaultProgram, createNewProgram, seedExerciseLibrary), suppression (deleteAll) des données atomiques.
//  Utilisé par : MuscuApp (RootView), NewProgramSheet, ProgramEditorEmptyView.
//

import Foundation
import SwiftData

@MainActor
final class DataController {

    /// Vide toutes les données du programme atomique (TrainingProgram, ExerciseMaster, SessionRecipe, etc.).
    /// À utiliser avant de rappeler createDefaultProgram pour forcer une régénération.
    static func deleteAll(context: ModelContext) {
        print("[DataController] deleteAll called")

        do {
            let sessionEx = try context.fetch(FetchDescriptor<SessionExercise>())
            for o in sessionEx { context.delete(o) }

            let recipes = try context.fetch(FetchDescriptor<SessionRecipe>())
            for o in recipes { context.delete(o) }

            let programs = try context.fetch(FetchDescriptor<TrainingProgram>())
            for o in programs { context.delete(o) }

            let masters = try context.fetch(FetchDescriptor<ExerciseMaster>())
            for o in masters { context.delete(o) }

            try context.save()
            print("[DataController] deleteAll completed")
        } catch {
            print("[DataController] deleteAll error: \(error)")
        }
    }

    /// Crée le programme "Programme Volley & Détente" (8 semaines) **uniquement si la base ne contient aucun programme**.
    /// Ne jamais appeler si des données existent (évite doublons et corruptions).
    /// 100 % atomique : TrainingProgram → TrainingWeek → TrainingDay → SessionRecipe → SessionExercise → ExerciseMaster.
    static func createDefaultProgram(context: ModelContext) async {
        print("[DataController] createDefaultProgram called")

        let fetch = FetchDescriptor<TrainingProgram>()
        let existing = (try? context.fetch(fetch)) ?? []
        guard existing.isEmpty else {
            print("[DataController] createDefaultProgram: data already exists (\(existing.count) programme(s)), skipping")
            return
        }

        print("[DataController] createDefaultProgram: starting Programme Athlétique Volley seeding...")

        // 1) Bibliothèque d’exercices (ExerciseMaster)
        let mastersByName = await createExerciseLibrary(context: context)

        let program = TrainingProgram(
            name: "Programme Athlétique Volley",
            programDescription: "8 semaines – Haut du corps, bas du corps, pliométrie et détente. Semaines impaires = Dimanche A, paires = Dimanche B.",
            sportCategoriesString: "volley,general",
            validationRules: nil,
            isTemplate: true
        )
        context.insert(program)

        let builder = VolleyProgramBuilder(context: context, masters: mastersByName)

        for weekNumber in 1...8 {
            let week = TrainingWeek(weekNumber: weekNumber)
            week.program = program
            context.insert(week)
            program.weeks.append(week)

            for dayIndex in 0..<7 {
                let (isRest, focus, title) = VolleyProgramBuilder.dayConfig(dayIndex: dayIndex)
                let day = TrainingDay(
                    dayIndex: dayIndex,
                    isRestDay: isRest,
                    focusCategory: focus,
                    title: title
                )
                day.week = week
                context.insert(day)
                week.days.append(day)
            }
        }

        let weeks = program.weeks.sorted { $0.weekNumber < $1.weekNumber }
        for w in weeks {
            let block = VolleyProgramBuilder.block(for: w.weekNumber)
            let days = w.days.sorted { $0.dayIndex < $1.dayIndex }
            guard days.count == 7 else { continue }

            let d0 = days[0], d1 = days[1], d2 = days[2], d3 = days[3], d4 = days[4], d5 = days[5], d6 = days[6]

            d2.isRestDay = true
            d2.focusCategory = .none
            d2.title = "Repos total"

            builder.attachRecipe(to: d3, name: "Entraînement Volley", goal: .technique, bodyFocus: .fullBody, lines: VolleyProgramBuilder.jeudiVolleyLine())

            d5.isRestDay = false
            d5.focusCategory = .hybrid
            d5.title = "Repos Actif (Mobilité)"
            builder.attachRecipe(to: d5, name: "Repos Actif (Mobilité)", goal: .rehab, bodyFocus: .fullBody, lines: VolleyProgramBuilder.samediMobiliteLines())

            let isOddWeek = (w.weekNumber % 2) == 1
            builder.fillWeek(weekNumber: w.weekNumber, block: block, isOddWeek: isOddWeek, d0: d0, d1: d1, d4: d4, d6: d6)
        }


        do {
            try context.save()
            print("[DataController] createDefaultProgram: Programme Athlétique Volley seeding completed")
        } catch {
            print("[DataController] createDefaultProgram error: \(error)")
        }
    }

    /// Crée la bibliothèque exhaustive d’exercices (Haut, Bas, Plio, Core, Mobilité) et retourne [nom: ExerciseMaster].
    /// Si des masters existent déjà, retourne le dictionnaire sans rien insérer (évite doublons).
    static func createExerciseLibrary(context: ModelContext) async -> [String: ExerciseMaster] {
        let fetch = FetchDescriptor<ExerciseMaster>()
        let existing = (try? context.fetch(fetch)) ?? []
        if existing.isEmpty {
            let library = Self.exerciseLibraryEntries()
            for entry in library {
                let master = ExerciseMaster(
                    name: entry.name,
                    visualAsset: "figure.strengthtraining.traditional",
                    videoUrl: nil,
                    exerciseDescription: "Exercice : \(entry.name)",
                    musclesTargetedString: entry.musclesTargetedString,
                    defaultRestTime: 60
                )
                context.insert(master)
            }

            do {
                try context.save()
                print("[DataController] createExerciseLibrary: \(library.count) exercices insérés et sauvegardés.")
            } catch {
                print("[DataController] createExerciseLibrary error: \(error)")
            }
        }

        // Toujours s'assurer que la bibliothèque étendue et les exercices "Fighter Performance" existent.
        await createExtendedExerciseLibrary(context: context)
        ensureFighterPerformanceMasters(context: context)

        let all = (try? context.fetch(FetchDescriptor<ExerciseMaster>())) ?? []
        print("📚 Bibliothèque totale : \(all.count) exercices chargés.")
        return Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })
    }

    // MARK: - Hybrid Programs Seeding

    /// Crée 5 programmes hybrides (combat, endurance, raquette, outdoor, bien‑être) si absents.
    /// Utilise TrainingProgram/TrainingWeek/TrainingDay comme gabarit atomique.
    static func seedHybridPrograms(context: ModelContext) async {
        print("[DataController] seedHybridPrograms called")

        let fetch = FetchDescriptor<TrainingProgram>()
        let existing = (try? context.fetch(fetch)) ?? []
        let existingNames = Set(existing.map { $0.name })

        struct HybridDef {
            let name: String
            let description: String
            let sportCategories: [SportCategory]
            let dayTitles: [String]
        }

        let programs: [HybridDef] = [
            HybridDef(
                name: "Combat Sports (Striking & Grappling)",
                description: "Bloc hybride orienté sports de combat : technique, HIIT, mobilité et force explosive.",
                sportCategories: [.boxing, .general],
                dayTitles: [
                    "J1 · Technique Pure (Shadow/Drills)",
                    "J2 · Conditionnement HIIT (Sac/Sprints)",
                    "J3 · Mobilité & Hanche",
                    "J4 · Force Explosive (Lests)",
                    "J5 · Sparring ou Situation",
                    "J6 · Travail de Pieds & Réflexes"
                ]
            ),
            HybridDef(
                name: "Endurance et Cardio",
                description: "Cycle d’endurance (Zone 2, fractionné, tempo, sorties longues) avec renforcement.",
                sportCategories: [.running, .general],
                dayTitles: [
                    "J1 · Sortie Zone 2 (Récup active)",
                    "J2 · Fractionné Court (Vitesse)",
                    "J3 · Renforcement Musculaire (Core/Jambes)",
                    "J4 · Tempo Run/Ride",
                    "J5 · Technique Spécifique",
                    "J6 · Sortie Longue (Volume)"
                ]
            ),
            HybridDef(
                name: "Sports de Raquette",
                description: "Programme raquettes : footwork, matchs dirigés, prévention et pliométrie.",
                sportCategories: [.general],
                dayTitles: [
                    "J1 · Footwork (Échelle de rythme)",
                    "J2 · Match ou Entraînement dirigé",
                    "J3 · Prévention (Épaule/Poignet)",
                    "J4 · Plyométrie (Détente)",
                    "J5 · Match ou Tactique",
                    "J6 · Mobilité Thoracique & Rotation"
                ]
            ),
            HybridDef(
                name: "Outdoor et Montagne",
                description: "Préparation outdoor/montagne : force de préhension, côtes, gainage et yoga.",
                sportCategories: [.general],
                dayTitles: [
                    "J1 · Force de Préhension / Doigts",
                    "J2 · Sortie Intensité (Côtes)",
                    "J3 · Gainage Profond & Équilibre",
                    "J4 · Force Bas du Corps (Squats/Fentes)",
                    "J5 · Yoga pour Montagnard",
                    "J6 · Sortie Longue / Aventure"
                ]
            ),
            HybridDef(
                name: "Bien‑être et Mobilité",
                description: "Bloc axé bien‑être : Pilates, Vinyasa, Yin, mobilité contrôlée et méditation.",
                sportCategories: [.general],
                dayTitles: [
                    "J1 · Pilates (Force du centre)",
                    "J2 · Vinyasa Yoga (Flow dynamique)",
                    "J3 · Travail d'Inversion / Équilibre",
                    "J4 · Yin Yoga (Étirements profonds)",
                    "J5 · Mobilité Articulaire Contrôlée (CARS)",
                    "J6 · Flow Libre / Méditation"
                ]
            ),
            HybridDef(
                name: "Fighter Performance (No Gym)",
                description: "Programme combat sans salle : technique, HIIT, mobilité, force explosive, sac et footwork.",
                sportCategories: [.boxing, .general],
                dayTitles: [
                    "J1 · Technique & Shadow Boxing — Fluidité et gestuelle",
                    "J2 · HIIT Conditioning — Puissance sous fatigue",
                    "J3 · Mobilité & Hanches — Souplesse spécifique combat",
                    "J4 · Force Explosive — Puissance de frappe/saisie",
                    "J5 · Sparring / Sac — Application réelle",
                    "J6 · Footwork & Agilité — Placement et réaction"
                ]
            )
        ]

        var createdCount = 0

        for def in programs where !existingNames.contains(def.name) {
            let program = TrainingProgram(
                name: def.name,
                programDescription: def.description,
                sportCategoriesString: def.sportCategories.map(\.rawValue).joined(separator: ","),
                validationRules: nil,
                isTemplate: true
            )
            context.insert(program)

            let week = TrainingWeek(weekNumber: 1)
            week.program = program
            context.insert(week)
            program.weeks.append(week)

            for (index, title) in def.dayTitles.enumerated() {
                let day = TrainingDay(
                    dayIndex: index,
                    isRestDay: false,
                    focusCategory: .hybrid,
                    title: title
                )
                day.week = week
                context.insert(day)
                week.days.append(day)
            }

            createdCount += 1
        }

        if createdCount == 0 {
            print("[DataController] seedHybridPrograms: all hybrid programs already exist, skipping")
        } else {
            do {
                try context.save()
                print("[DataController] seedHybridPrograms: \(createdCount) programme(s) hybrides créés.")
            } catch {
                print("[DataController] seedHybridPrograms error: \(error)")
            }
        }
    }

    // MARK: - Initial Data Seeding (Library + Hybrid Programs)

    /// Seed initial de la base : bibliothèque d'exercices + programmes hybrides.
    /// Appelé juste après validation de l'onboarding.
    static func seedInitialData(context: ModelContext) async {
        print("[DataController] seedInitialData called")

        let existingPrograms = (try? context.fetch(FetchDescriptor<TrainingProgram>())) ?? []
        let existingMasters = (try? context.fetch(FetchDescriptor<ExerciseMaster>())) ?? []

        if existingMasters.isEmpty {
            _ = await createExerciseLibrary(context: context)
        }

        if existingPrograms.isEmpty {
            await seedHybridPrograms(context: context)
            // Une fois les templates disponibles, génère un programme personnalisé à partir du profil et du planning.
            generatePersonalizedProgram(context: context)
        } else {
            print("[DataController] seedInitialData: programs already exist (\(existingPrograms.count)), skipping seeding.")
        }
    }

    /// Génère le programme personnalisé (non-template) à partir des gabarits et du planning par discipline.
    /// - Parameters:
    ///   - context: Contexte SwiftData courant.
    ///   - force: Si true, supprime le programme actif existant avant de régénérer.
    static func generatePersonalizedProgram(context: ModelContext, force: Bool = false) {
        print("[DataController] generatePersonalizedProgram called (force=\(force))")

        let profiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        guard let profile = profiles.first else {
            print("[DataController] generatePersonalizedProgram: aucun profil trouvé.")
            return
        }

        // Si un programme actif existe déjà, on peut soit le conserver, soit le recréer en mode "force".
        if let existingActive = profile.activeTrainingProgram {
            if force {
                print("[DataController] generatePersonalizedProgram: suppression de l'ancien programme actif avant régénération.")
                profile.activeTrainingProgram = nil
                context.delete(existingActive)
            } else {
                print("[DataController] generatePersonalizedProgram: activeTrainingProgram déjà défini, skip.")
                return
            }
        }

        let templates = availableProgramTemplates(for: profile, context: context)
        let disciplines = profile.selectedDisciplines
        guard !disciplines.isEmpty else {
            print("[DataController] generatePersonalizedProgram: aucune discipline sélectionnée.")
            return
        }

        let programName = "Programme Hybride Personnel"
        let description = "Plan généré automatiquement à partir de tes disciplines et de ton planning."
        let allCategories = sportCategories(for: disciplines)

        let activeProgram = TrainingProgram(
            name: programName,
            programDescription: description,
            sportCategoriesString: allCategories.map(\.rawValue).joined(separator: ","),
            validationRules: nil,
            isTemplate: false
        )
        context.insert(activeProgram)

        let week = TrainingWeek(weekNumber: 1)
        week.program = activeProgram
        context.insert(week)
        activeProgram.weeks.append(week)

        // 1. Sessions par discipline (Muscu + autres).
        buildDisciplineDays(
            for: profile,
            in: activeProgram,
            week: week,
            templates: templates,
            context: context
        )

        profile.activeTrainingProgram = activeProgram

        do {
            try context.save()
            print("[DataController] generatePersonalizedProgram: programme actif généré avec succès.")
        } catch {
            print("[DataController] generatePersonalizedProgram error: \(error)")
        }
    }

    /// Liste stricte de la bibliothèque : nom exact + catégorie (Haut, Bas, Plio, Core, Mobilité).
    private static func exerciseLibraryEntries() -> [(name: String, musclesTargetedString: String)] {
        let haut = "chest,back,shoulders,arms"
        let bas = "legs"
        let plio = "fullBody"
        let core = "core"
        let mobilite = "fullBody"

        return [
            // 1. Musculation Haut
            ("Développé couché haltères", haut),
            ("Développé couché haltères inclinés", haut),
            ("Tirage vertical", haut),
            ("Développé militaire", haut),
            ("Rowing barre", haut),
            ("Tractions prise supination", haut),
            ("Dips", haut),
            ("Push press", haut),
            ("Haltères row renegade + pompes", haut),
            ("Élévations latérales", haut),
            ("Pompes 1 bras glissées", haut),
            ("Bent over shoulder raise", haut),
            ("Pompes explosives + planche large", haut),
            // 2. Musculation Bas
            ("Back squat", bas),
            ("Soulevé de terre roumain", bas),
            ("Fentes avant en absorption", bas),
            ("Box squat unilatéral", bas),
            ("Fentes statiques isométrie avec haltères", bas),
            ("Élevations mollets haltères", bas),
            ("Élevations mollets athlétiques", bas),
            ("Fentes bulgares explosives haltères", bas),
            ("Fentes latérales haltères", bas),
            ("Fentes statiques + step up & push press", bas),
            ("Curl Nordic", bas),
            ("Step up haltères", bas),
            ("Pont fessier amplitude", bas),
            ("FDH pose du sprinter isométrie", bas),
            // 3. Pliométrie & Vitesse
            ("Sprint 30m", plio),
            ("Sprint 40m", plio),
            ("Sprint 50m", plio),
            ("Pas fléchis latéraux", plio),
            ("Accélération / Décélération 3 plots", plio),
            ("Saut vertical haltères", plio),
            ("Saut vertical assis haltères", plio),
            ("Saut vertical pur (CMJ max)", plio),
            ("Depth jump", plio),
            ("Broad jump enchaînés", plio),
            ("Skater jump", plio),
            ("MB pivot jump", plio),
            ("Ankle hop frontal + latéral", plio),
            ("Double rebond alternatif", plio),
            ("Skater jump + vertical jump unilatéral", plio),
            ("Saut frontal + saut latéral max", plio),
            ("Fentes sautées + stabilité", plio),
            ("Saut latéral explosif à genoux", plio),
            ("Saut cheville latéral x3", plio),
            ("Depth jump haltères + saut vertical", plio),
            ("Décélération rapide", plio),
            // 4. Core
            ("Bear Crawl planche superman", core),
            ("Pallof press", core),
            ("Dead bug", core),
            ("Hip Turn Cable Side Chop", core),
            ("MB fente slam rotation", core),
            ("Carry Valise", core),
            ("Rotation de hanche explosive", core),
            ("Cable pivot row", core),
            ("Core knee drive", core),
            ("Planche adducteurs", core),
            ("Pivot jab swipe + press MB", core),
            // 5. Mobilité
            ("Cardio léger", mobilite),
            ("Entraînement Volley", mobilite),
            ("Ouvertures thoraciques au sol", mobilite),
            ("Rotations d'épaules avec élastique", mobilite),
            ("Étirement des pectoraux", mobilite),
            ("Étirements poignets", mobilite),
            ("Squat profond maintenu", mobilite),
            ("Étirement des fléchisseurs de la hanche", mobilite),
            ("Dorsiflexion de la cheville", mobilite),
        ]
    }

    /// Ajoute les exercices spécifiques Fighter Performance à la bibliothèque si manquants.
    private static func ensureFighterPerformanceMasters(context: ModelContext) {
        let fighterEntries: [(name: String, desc: String, muscles: String)] = [
            ("Shadow Boxing", "Enchaînement de boxe dans le vide pour travailler la technique et la fluidité sans impact.", "fullBody"),
            ("Burpees / Sprawls", "Mouvement explosif au sol simulant le sprawl de lutte, très exigeant métaboliquement.", "fullBody"),
            ("90/90 Hip Switch", "Rotation contrôlée des hanches en position 90/90 pour améliorer la mobilité et la stabilité.", "legs"),
            ("Cossack Squats", "Squats latéraux profonds pour renforcer les adducteurs et la mobilité des hanches.", "legs"),
            ("Pompes explosives", "Pompes avec phase de projection des mains (ou clap) pour développer la puissance de poussée.", "chest,arms"),
            ("Kettlebell Swings", "Balancés de kettlebell développant la puissance de hanche et le cardio.", "legs,back"),
            ("Échelle de rythme", "Drills de footwork rapides sur échelle de rythme pour la coordination et la vitesse.", "fullBody")
        ]

        let existing = (try? context.fetch(FetchDescriptor<ExerciseMaster>())) ?? []
        let existingNames = Set(existing.map { $0.name })

        var inserted = 0
        for entry in fighterEntries where !existingNames.contains(entry.name) {
            let master = ExerciseMaster(
                name: entry.name,
                visualAsset: "figure.strengthtraining.traditional",
                videoUrl: nil,
                exerciseDescription: entry.desc,
                musclesTargetedString: entry.muscles,
                defaultRestTime: 60
            )
            context.insert(master)
            inserted += 1
        }

        if inserted > 0 {
            do {
                try context.save()
                print("[DataController] ensureFighterPerformanceMasters: \(inserted) master(s) ajoutés.")
            } catch {
                print("[DataController] ensureFighterPerformanceMasters error: \(error)")
            }
        }
    }

    /// Alias pour compatibilité (RootView appelle seedExerciseLibraryAndSampleSession).
    static func seedExerciseLibraryAndSampleSession(context: ModelContext) async {
        _ = await createExerciseLibrary(context: context)
    }

    /// Crée un nouveau programme « vierge » avec 1 semaine et 7 jours vides.
    /// - Parameters:
    ///   - context: ModelContext SwiftData courant.
    ///   - name: Nom du programme.
    ///   - category: Catégorie sportive principale.
    /// - Returns: Le TrainingProgram nouvellement créé (déjà inséré et sauvegardé).
    @discardableResult
    static func createNewProgram(context: ModelContext, name: String, category: SportCategory) -> TrainingProgram {
        let program = TrainingProgram(
            name: name,
            programDescription: "",
            sportCategoriesString: category.rawValue
        )
        context.insert(program)

        // Une seule semaine (Semaine 1)
        let week = TrainingWeek(weekNumber: 1)
        week.program = program
        context.insert(week)
        program.weeks.append(week)

        // Sept jours vides (indices 0...6), sans séance ni exercices
        for dayIndex in 0..<7 {
            let day = TrainingDay(
                dayIndex: dayIndex,
                isRestDay: false,
                focusCategory: .none,
                title: "Jour \(dayIndex + 1)"
            )
            day.week = week
            context.insert(day)
            week.days.append(day)
        }

        do {
            try context.save()
        } catch {
            print("[DataController] createNewProgram error: \(error)")
        }

        return program
    }

    // MARK: - Program templates filtering

    /// Retourne les programmes gabarits pertinents pour le profil donné (discipline + accès salle).
    static func availableProgramTemplates(for profile: UserProfile, context: ModelContext) -> [TrainingProgram] {
        let fetch = FetchDescriptor<TrainingProgram>()
        let all = (try? context.fetch(fetch)) ?? []
        let templates = all.filter { $0.isTemplate }
        let wantedCategories = sportCategories(for: profile.selectedDisciplines)

        return templates.filter { program in
            let cats = Set(program.sportCategories)
            // Programmes universels : toujours visibles.
            let disciplineMatch = cats.contains(.general) || !cats.isDisjoint(with: wantedCategories)
            guard disciplineMatch else { return false }

            // Filtre matériel : si pas de salle, on exclut les variantes "Gym Edition".
            if profile.hasGymAccess {
                return true
            } else {
                let lowerName = program.name.lowercased()
                if lowerName.contains("gym") && !lowerName.contains("no gym") {
                    return false
                }
                return true
            }
        }
    }

    /// Poids suggéré pour un exercice quand la charge est en % du 1RM (loadStrategy == .percentageOfOneRM).
    /// Utilise ExerciseMaster.estimatedOneRM et le loadValue du SessionExercise (ex: 80 = 80%).
    static func suggestedWeight(for master: ExerciseMaster?, percentage: Double) -> Double? {
        guard let master = master, master.estimatedOneRM > 0, percentage > 0 else { return nil }
        return OneRMHelper.weightForPercentage(of: master.estimatedOneRM, percentage: percentage)
    }
}

/// Mapping Disciplines → catégories sportives associées (partagé avec ProgramListView).
private func sportCategories(for disciplines: Set<Discipline>) -> Set<SportCategory> {
    disciplines.reduce(into: Set<SportCategory>()) { acc, d in
        switch d {
        case .combat:
            acc.insert(.boxing)
        case .endurance:
            acc.insert(.running)
        case .racket:
            acc.insert(.general)
        case .outdoor:
            acc.insert(.general)
        case .wellness:
            acc.insert(.general)
        case .strength:
            acc.insert(.bodybuilding)
        case .street:
            acc.insert(.bodybuilding)
        case .ballSports:
            acc.insert(.basket); acc.insert(.volley)
        }
    }
}

// MARK: - Programme personnalisé (construction des jours / recettes)

/// Construit les jours de la semaine (TrainingDay + SessionRecipe) à partir du planning disciplinaire.
private func buildDisciplineDays(
    for profile: UserProfile,
    in program: TrainingProgram,
    week: TrainingWeek,
    templates: [TrainingProgram],
    context: ModelContext
) {
    let schedule = profile.disciplineSchedule
    guard !schedule.isEmpty else { return }

    // Tri des disciplines pour une itération stable.
    let orderedDisciplines = schedule.keys.sorted { $0.displayName < $1.displayName }

    struct PendingDay {
        let dayOfWeek: DayOfWeek
        let title: String
        let focusCategory: FocusCategory
        /// Recette source à cloner (templates). Nil pour les jours de musculation générés.
        let sourceRecipe: SessionRecipe?
        /// Nom de la recette pour les jours générés (Muscu).
        let strengthLabel: String?
    }

    var pendingDays: [PendingDay] = []

    // 1) Discipline Muscu (strength) avec logique Upper/Lower ou PPL.
    if let strengthDays = schedule[.strength], !strengthDays.isEmpty {
        let sortedStrengthDays = strengthDays.sorted { $0.rawValue < $1.rawValue }
        for (idx, dayOfWeek) in sortedStrengthDays.enumerated() {
            let titlePrefix = frenchWeekdayName(for: dayOfWeek)
            let (focus, label) = strengthFocusLabel(forDayIndex: idx, totalDays: sortedStrengthDays.count)
            let dayTitle = "\(titlePrefix) - \(label)"

            pendingDays.append(
                PendingDay(
                    dayOfWeek: dayOfWeek,
                    title: dayTitle,
                    focusCategory: focus,
                    sourceRecipe: nil,
                    strengthLabel: label
                )
            )
        }
    }

    // 2) Autres disciplines : clonage depuis un template si disponible.
    for discipline in orderedDisciplines where discipline != .strength {
        guard let days = schedule[discipline], !days.isEmpty else { continue }
        guard let template = templateProgram(for: discipline, in: templates) else { continue }

        let nonRestDays = (template.weeks.first?.days ?? [])
            .sorted { $0.dayIndex < $1.dayIndex }
            .filter { !$0.isRestDay }
        guard !nonRestDays.isEmpty else { continue }

        let sortedDays = days.sorted { $0.rawValue < $1.rawValue }

        for (offset, dayOfWeek) in sortedDays.enumerated() {
            let sourceDay = nonRestDays[offset % nonRestDays.count]
            let sourceTitle = sourceDay.title.isEmpty ? discipline.displayName : sourceDay.title
            let weekdayName = frenchWeekdayName(for: dayOfWeek)
            let sessionTitle = "\(weekdayName) - \(sourceTitle)"

            let pending = PendingDay(
                dayOfWeek: dayOfWeek,
                title: sessionTitle,
                focusCategory: sourceDay.focusCategory,
                sourceRecipe: sourceDay.sessionRecipe,
                strengthLabel: nil
            )
            pendingDays.append(pending)
        }
    }

    // Regroupe les PendingDay par jour de semaine pour un accès O(1).
    let pendingByDay = Dictionary(grouping: pendingDays, by: { $0.dayOfWeek })

    // Template "Bien‑être et Mobilité" pour les jours de récupération active.
    let wellnessTemplate = templateProgram(for: .wellness, in: templates)
    let wellnessNonRestDays: [TrainingDay] = (wellnessTemplate?.weeks.first?.days ?? [])
        .sorted { $0.dayIndex < $1.dayIndex }
        .filter { !$0.isRestDay && $0.sessionRecipe != nil }

    var activeRecoveryUsed = 0
    let maxActiveRecovery = 2

    // 3) Boucle sur les 7 jours de la semaine (Lundi…Dimanche), dayIndex = 0…6.
    for dayOfWeek in DayOfWeek.allCases {
        let dayIndex = dayOfWeek.rawValue

        if let pending = pendingByDay[dayOfWeek]?.first {
            // Jour planifié (Muscu / autre discipline).
            let day = TrainingDay(
                dayIndex: dayIndex,
                isRestDay: false,
                focusCategory: pending.focusCategory,
                title: pending.title
            )
            day.week = week
            context.insert(day)
            week.days.append(day)

            if let sourceRecipe = pending.sourceRecipe {
                // Clonage simple de la recette template.
                let cloned = cloneSessionRecipe(sourceRecipe, for: day, context: context)
                day.sessionRecipe = cloned
            } else if let strengthLabel = pending.strengthLabel {
                // Jour de musculation généré (Upper/Lower/PPL/Full Body).
                let bodyFocus: BodyFocus
                switch pending.focusCategory {
                case .upperBody: bodyFocus = .upper
                case .legs: bodyFocus = .lower
                case .push: bodyFocus = .upper
                case .pull: bodyFocus = .upper
                default: bodyFocus = .fullBody
                }
                let recipe = SessionRecipe(
                    name: strengthLabel,
                    goal: .strength,
                    bodyFocus: bodyFocus,
                    sportCategoriesString: "bodybuilding"
                )
                recipe.day = day
                day.sessionRecipe = recipe
                context.insert(recipe)
            }
        } else {
            // Jour non planifié : Repos total ou Récupération active (Bien‑être & Mobilité).
            let weekdayName = frenchWeekdayName(for: dayOfWeek)

            var isRestDay = true
            var focus: FocusCategory = .none
            var title = "\(weekdayName) - Repos total"
            var recipeToClone: SessionRecipe?

            if activeRecoveryUsed < maxActiveRecovery,
               let sourceDay = wellnessNonRestDays.indices.contains(activeRecoveryUsed) ? wellnessNonRestDays[activeRecoveryUsed] : nil,
               let sourceRecipe = sourceDay.sessionRecipe {
                // Récupération active : on clone une journée du template Bien‑être & Mobilité.
                isRestDay = false
                focus = .hybrid
                title = "\(weekdayName) - Récupération active"
                recipeToClone = sourceRecipe
                activeRecoveryUsed += 1
            }

            let day = TrainingDay(
                dayIndex: dayIndex,
                isRestDay: isRestDay,
                focusCategory: focus,
                title: title
            )
            day.week = week
            context.insert(day)
            week.days.append(day)

            if let sourceRecipe = recipeToClone {
                let cloned = cloneSessionRecipe(sourceRecipe, for: day, context: context)
                day.sessionRecipe = cloned
            }
        }
    }

    // 4) Optimisation hybride : injection de pliométrie si Muscu + sport explosif.
    let hasStrength = schedule[.strength]?.isEmpty == false
    let hasExplosiveSport = schedule[.combat]?.isEmpty == false || schedule[.ballSports]?.isEmpty == false
    if hasStrength && hasExplosiveSport {
        injectPlyometricsIntoStrengthDays(in: week, context: context)
    }
}

/// Détermine le focus Upper/Lower ou PPL pour les jours de musculation.
private func strengthFocusLabel(forDayIndex index: Int, totalDays: Int) -> (FocusCategory, String) {
    if totalDays == 1 {
        return (.hybrid, "Full Body Force")
    } else if totalDays == 2 {
        return index == 0 ? (.upperBody, "Upper Body Strength") : (.legs, "Lower Body Strength")
    } else {
        // 3 jours ou plus → PPL / Full Body mix
        switch index % 3 {
        case 0: return (.push, "Push (Pecs/Épaules/Triceps)")
        case 1: return (.pull, "Pull (Dos/Biceps)")
        default: return (.legs, "Legs (Jambes/Fessiers)")
        }
    }
}

/// Retourne le nom français du jour (ex: "Lundi").
private func frenchWeekdayName(for day: DayOfWeek) -> String {
    switch day {
    case .monday: return "Lundi"
    case .tuesday: return "Mardi"
    case .wednesday: return "Mercredi"
    case .thursday: return "Jeudi"
    case .friday: return "Vendredi"
    case .saturday: return "Samedi"
    case .sunday: return "Dimanche"
    }
}

/// Sélectionne un programme template pertinent pour une discipline donnée.
private func templateProgram(for discipline: Discipline, in templates: [TrainingProgram]) -> TrainingProgram? {
    // Filtre par catégorie sportive associée.
    let wantedCats = sportCategories(for: [discipline])
    let filtered = templates.filter { program in
        let cats = Set(program.sportCategories)
        return !cats.isDisjoint(with: wantedCats) || cats.contains(.general)
    }

    if filtered.isEmpty { return nil }

    // Tentative de match par nom sémantique.
    let lowerNameMatches: (TrainingProgram) -> Bool = { program in
        let name = program.name.lowercased()
        switch discipline {
        case .combat: return name.contains("combat") || name.contains("fighter") || name.contains("boxe")
        case .endurance: return name.contains("endurance") || name.contains("cardio")
        case .racket: return name.contains("raquette")
        case .outdoor: return name.contains("outdoor") || name.contains("montagne")
        case .wellness: return name.contains("bien") || name.contains("mobilité") || name.contains("yoga")
        case .strength: return name.contains("fighter performance") || name.contains("force")
        case .street: return name.contains("street")
        case .ballSports: return name.contains("basket") || name.contains("volley") || name.contains("ballon")
        }
    }

    if let match = filtered.first(where: lowerNameMatches) {
        return match
    }
    return filtered.first
}

/// Clone un SessionRecipe (et ses SessionExercise) sur un nouveau TrainingDay.
private func cloneSessionRecipe(_ source: SessionRecipe, for day: TrainingDay, context: ModelContext) -> SessionRecipe {
    let cloned = SessionRecipe(
        name: source.name,
        goal: source.goal,
        bodyFocus: source.bodyFocus,
        sportCategoriesString: source.sportCategoriesString
    )
    cloned.day = day
    context.insert(cloned)

    for se in source.exercises {
        let clonedSE = SessionExercise(
            sets: se.sets,
            reps: se.reps,
            restTime: se.restTime,
            loadStrategy: se.loadStrategy,
            loadValue: se.loadValue
        )
        clonedSE.exercise = se.exercise
        clonedSE.session = cloned
        context.insert(clonedSE)
        cloned.exercises.append(clonedSE)
    }

    return cloned
}

/// Ajoute des blocs de pliométrie dans les jours Muscu quand l'utilisateur combine Force + Sport explosif.
private func injectPlyometricsIntoStrengthDays(in week: TrainingWeek, context: ModelContext) {
    let days = week.days.filter { !$0.isRestDay && ($0.focusCategory == .upperBody || $0.focusCategory == .legs || $0.focusCategory == .hybrid || $0.focusCategory == .push || $0.focusCategory == .pull) }
    guard !days.isEmpty else { return }

    let masters = (try? context.fetch(FetchDescriptor<ExerciseMaster>())) ?? []
    let byName = Dictionary(uniqueKeysWithValues: masters.map { ($0.name, $0) })

    // Liste courte d’exercices pliométriques à forte synergie athlétique.
    let plyoCandidates = [
        "Saut vertical pur (CMJ max)",
        "Depth jump",
        "Sprint 30m",
        "Skater jump"
    ]

    let plyoMasters: [ExerciseMaster] = plyoCandidates.compactMap { byName[$0] }
    guard !plyoMasters.isEmpty else { return }

    for (idx, day) in days.enumerated() {
        if day.sessionRecipe == nil {
            let recipe = SessionRecipe(
                name: day.title,
                goal: .volume,
                bodyFocus: .fullBody,
                sportCategoriesString: "bodybuilding"
            )
            recipe.day = day
            day.sessionRecipe = recipe
            context.insert(recipe)
        }
        guard let recipe = day.sessionRecipe else { continue }

        // Ajoute 1 exercice pliométrique différent par jour (cycle).
        let master = plyoMasters[idx % plyoMasters.count]
        let se = SessionExercise(
            sets: 3,
            reps: "5",
            restTime: 90,
            loadStrategy: .fixedWeight,
            loadValue: 0
        )
        se.exercise = master
        se.session = recipe
        context.insert(se)
        recipe.exercises.append(se)
    }
}

// MARK: - Volley Programme Builder (8 semaines, atomique uniquement)

private struct VolleyProgramBuilder {
    let context: ModelContext
    let masters: [String: ExerciseMaster]

    struct Line {
        let name: String
        let sets: Int
        let reps: String
        let rest: Int
    }

    static func block(for weekNumber: Int) -> Int {
        switch weekNumber {
        case 1...2: return 1
        case 3...4: return 2
        case 5...6: return 3
        case 7...8: return 4
        default: return 1
        }
    }

    static func dayConfig(dayIndex: Int) -> (Bool, FocusCategory, String) {
        switch dayIndex {
        case 0: return (false, .upperBody, "Haut du corps + Core")
        case 1: return (false, .plyometrics, "Volley + Micro-Pliométrie")
        case 2: return (true, .none, "Repos total")
        case 3: return (false, .hybrid, "Entraînement Volley")
        case 4: return (false, .legs, "Bas du corps 1")
        case 5: return (false, .hybrid, "Repos Actif (Mobilité)")
        case 6: return (false, .legs, "Dimanche A/B")
        default: return (true, .none, "Repos")
        }
    }

    func attachRecipe(to day: TrainingDay, name: String, goal: SessionGoal, bodyFocus: BodyFocus, lines: [Line]) {
        day.title = name
        day.isRestDay = false
        let recipe = SessionRecipe(
            name: name,
            goal: goal,
            bodyFocus: bodyFocus,
            sportCategoriesString: "volley,general"
        )
        context.insert(recipe)
        recipe.day = day
        day.sessionRecipe = recipe
        for line in lines {
            guard let master = masters[line.name] else { continue }
            let se = SessionExercise(sets: line.sets, reps: line.reps, restTime: line.rest, loadStrategy: .fixedWeight, loadValue: 0)
            context.insert(se)
            se.exercise = master
            se.session = recipe
            recipe.exercises.append(se)
        }
    }

    func fillWeek(weekNumber: Int, block: Int, isOddWeek: Bool, d0: TrainingDay, d1: TrainingDay, d4: TrainingDay, d6: TrainingDay) {
        let lunLines = Self.lundiLines(block: block)
        let marLines = Self.mardiLines(block: block)
        let venLines = Self.vendrediLines(block: block)
        let dimALines = Self.dimancheALines(block: block)
        let dimBLines = Self.dimancheBLines()

        attachRecipe(to: d0, name: "Haut du corps + Core", goal: .volume, bodyFocus: .upper, lines: lunLines)
        d0.focusCategory = .upperBody

        attachRecipe(to: d1, name: "Volley + Micro-Pliométrie", goal: .technique, bodyFocus: .fullBody, lines: marLines)
        d1.focusCategory = .plyometrics

        attachRecipe(to: d4, name: "Bas du corps 1", goal: .strength, bodyFocus: .lower, lines: venLines)
        d4.focusCategory = .legs

        if isOddWeek {
            attachRecipe(to: d6, name: "Bas du corps 2 (Version A)", goal: .strength, bodyFocus: .lower, lines: dimALines)
        } else {
            attachRecipe(to: d6, name: "Détente Max (Version B)", goal: .technique, bodyFocus: .lower, lines: dimBLines)
        }
        d6.focusCategory = .legs
    }

    static func lundiLines(block: Int) -> [Line] {
        switch block {
        case 1:
            return [
                Line(name: "Développé couché haltères", sets: 3, reps: "10", rest: 90),
                Line(name: "Tirage vertical", sets: 3, reps: "10", rest: 90),
                Line(name: "Développé militaire", sets: 3, reps: "10", rest: 90),
                Line(name: "Rowing barre", sets: 3, reps: "10", rest: 90),
                Line(name: "Tractions prise supination", sets: 3, reps: "MAX", rest: 90),
                Line(name: "Dips", sets: 3, reps: "MAX", rest: 90),
                Line(name: "Bear Crawl planche superman", sets: 3, reps: "4", rest: 60),
                Line(name: "Pallof press", sets: 3, reps: "30s", rest: 45),
                Line(name: "Dead bug", sets: 3, reps: "8", rest: 45),
            ]
        case 2:
            return [
                Line(name: "Développé couché haltères", sets: 3, reps: "10", rest: 90),
                Line(name: "Push press", sets: 3, reps: "8", rest: 90),
                Line(name: "Haltères row renegade + pompes", sets: 3, reps: "10", rest: 90),
                Line(name: "Élévations latérales", sets: 3, reps: "10", rest: 90),
                Line(name: "Hip Turn Cable Side Chop", sets: 2, reps: "8", rest: 60),
                Line(name: "MB fente slam rotation", sets: 3, reps: "8", rest: 75),
                Line(name: "Carry Valise", sets: 3, reps: "20s", rest: 60),
            ]
        case 3:
            return [
                Line(name: "Développé couché haltères inclinés", sets: 3, reps: "7", rest: 105),
                Line(name: "Pompes 1 bras glissées", sets: 3, reps: "8", rest: 75),
                Line(name: "Tirage vertical", sets: 3, reps: "12", rest: 90),
                Line(name: "Développé militaire", sets: 4, reps: "10", rest: 60),
                Line(name: "Bent over shoulder raise", sets: 3, reps: "8", rest: 60),
                Line(name: "Dips", sets: 3, reps: "MAX", rest: 90),
                Line(name: "Tractions prise supination", sets: 3, reps: "MAX", rest: 90),
                Line(name: "Cable pivot row", sets: 3, reps: "8", rest: 75),
                Line(name: "Core knee drive", sets: 3, reps: "12", rest: 60),
            ]
        case 4:
            return [
                Line(name: "Développé couché haltères inclinés", sets: 3, reps: "7", rest: 105),
                Line(name: "Pompes 1 bras glissées", sets: 3, reps: "8", rest: 75),
                Line(name: "Tirage vertical", sets: 3, reps: "12", rest: 90),
                Line(name: "Élévations latérales", sets: 3, reps: "10", rest: 90),
                Line(name: "Pompes explosives + planche large", sets: 2, reps: "6", rest: 90),
                Line(name: "Dips", sets: 3, reps: "MAX", rest: 90),
                Line(name: "Tractions prise supination", sets: 3, reps: "MAX", rest: 90),
                Line(name: "Cable pivot row", sets: 3, reps: "8", rest: 75),
                Line(name: "Core knee drive", sets: 3, reps: "12", rest: 60),
            ]
        default: return []
        }
    }

    static func mardiLines(block: Int) -> [Line] {
        switch block {
        case 1:
            return [
                Line(name: "Sprint 30m", sets: 3, reps: "2", rest: 60),
                Line(name: "Pas fléchis latéraux", sets: 3, reps: "20s", rest: 30),
                Line(name: "Accélération / Décélération 3 plots", sets: 4, reps: "2", rest: 60),
            ]
        case 2:
            return [
                Line(name: "Sprint 40m", sets: 4, reps: "2", rest: 120),
                Line(name: "Rotation de hanche explosive", sets: 3, reps: "12", rest: 45),
                Line(name: "Double rebond alternatif", sets: 3, reps: "5", rest: 90),
            ]
        case 3:
            return [
                Line(name: "Sprint 30m", sets: 3, reps: "2", rest: 60),
                Line(name: "Skater jump + vertical jump unilatéral", sets: 3, reps: "6", rest: 75),
                Line(name: "Saut frontal + saut latéral max", sets: 2, reps: "4", rest: 75),
            ]
        case 4:
            return [
                Line(name: "Sprint 50m", sets: 5, reps: "1", rest: 90),
                Line(name: "Saut latéral explosif à genoux", sets: 3, reps: "5", rest: 75),
                Line(name: "Saut cheville latéral x3", sets: 3, reps: "3", rest: 60),
            ]
        default: return []
        }
    }

    static func vendrediLines(block: Int) -> [Line] {
        switch block {
        case 1:
            return [
                Line(name: "Saut vertical haltères", sets: 3, reps: "7", rest: 75),
                Line(name: "Back squat", sets: 3, reps: "8", rest: 90),
                Line(name: "Soulevé de terre roumain", sets: 3, reps: "8", rest: 90),
                Line(name: "Fentes avant en absorption", sets: 3, reps: "8", rest: 60),
            ]
        case 2:
            return [
                Line(name: "Saut vertical assis haltères", sets: 3, reps: "5", rest: 90),
                Line(name: "MB pivot jump", sets: 2, reps: "6", rest: 60),
                Line(name: "Fentes bulgares explosives haltères", sets: 3, reps: "6", rest: 105),
                Line(name: "Soulevé de terre roumain", sets: 3, reps: "8", rest: 90),
            ]
        case 3:
            return [
                Line(name: "Back squat", sets: 3, reps: "5", rest: 150),
                Line(name: "Saut vertical pur (CMJ max)", sets: 3, reps: "5", rest: 150),
                Line(name: "Fentes bulgares explosives haltères", sets: 3, reps: "7", rest: 105),
                Line(name: "Depth jump", sets: 3, reps: "6", rest: 90),
            ]
        case 4:
            return [
                Line(name: "Back squat", sets: 3, reps: "5", rest: 150),
                Line(name: "Saut vertical pur (CMJ max)", sets: 3, reps: "5", rest: 150),
                Line(name: "Depth jump haltères + saut vertical", sets: 3, reps: "5", rest: 90),
                Line(name: "Fentes bulgares explosives haltères", sets: 3, reps: "7", rest: 105),
            ]
        default: return []
        }
    }

    static func dimancheALines(block: Int) -> [Line] {
        switch block {
        case 1:
            return [
                Line(name: "FDH pose du sprinter isométrie", sets: 3, reps: "20s", rest: 45),
                Line(name: "Box squat unilatéral", sets: 3, reps: "8", rest: 60),
                Line(name: "Fentes statiques isométrie avec haltères", sets: 3, reps: "30s", rest: 60),
                Line(name: "Élevations mollets haltères", sets: 3, reps: "8", rest: 60),
                Line(name: "Hip Turn Cable Side Chop", sets: 2, reps: "8", rest: 60),
            ]
        case 2:
            return [
                Line(name: "Ankle hop frontal + latéral", sets: 3, reps: "20s", rest: 45),
                Line(name: "Fentes latérales haltères", sets: 3, reps: "7", rest: 75),
                Line(name: "Décélération rapide", sets: 3, reps: "10", rest: 45),
                Line(name: "Élevations mollets athlétiques", sets: 3, reps: "8", rest: 60),
            ]
        case 3:
            return [
                Line(name: "Fentes statiques + step up & push press", sets: 3, reps: "6", rest: 90),
                Line(name: "Fentes sautées + stabilité", sets: 3, reps: "6", rest: 90),
                Line(name: "Pont fessier amplitude", sets: 3, reps: "20s", rest: 90),
                Line(name: "Curl Nordic", sets: 3, reps: "6", rest: 105),
                Line(name: "Planche adducteurs", sets: 3, reps: "30s", rest: 60),
            ]
        case 4:
            return [
                Line(name: "Step up haltères", sets: 3, reps: "8", rest: 90),
                Line(name: "Pivot jab swipe + press MB", sets: 3, reps: "8", rest: 60),
                Line(name: "Pont fessier amplitude", sets: 3, reps: "20s", rest: 90),
                Line(name: "Planche adducteurs", sets: 3, reps: "45s", rest: 60),
            ]
        default: return []
        }
    }

    static func dimancheBLines() -> [Line] {
        return [
            Line(name: "Saut vertical pur (CMJ max)", sets: 4, reps: "3", rest: 150),
            Line(name: "Depth jump", sets: 3, reps: "3", rest: 150),
            Line(name: "Broad jump enchaînés", sets: 3, reps: "3", rest: 120),
            Line(name: "Skater jump", sets: 3, reps: "4", rest: 90),
        ]
    }

    /// Jeudi : Entraînement Volley (1x1).
    static func jeudiVolleyLine() -> [Line] {
        [Line(name: "Entraînement Volley", sets: 1, reps: "1", rest: 60)]
    }

    /// Samedi : Repos actif mobilité (Bloc 1–4 identique).
    static func samediMobiliteLines() -> [Line] {
        [
            Line(name: "Ouvertures thoraciques au sol", sets: 1, reps: "1", rest: 30),
            Line(name: "Rotations d'épaules avec élastique", sets: 1, reps: "1", rest: 30),
            Line(name: "Étirement des pectoraux", sets: 1, reps: "1", rest: 30),
            Line(name: "Étirements poignets", sets: 1, reps: "1", rest: 30),
            Line(name: "Squat profond maintenu", sets: 1, reps: "1", rest: 30),
            Line(name: "Étirement des fléchisseurs de la hanche", sets: 1, reps: "1", rest: 30),
            Line(name: "Dorsiflexion de la cheville", sets: 1, reps: "1", rest: 30),
        ]
    }
}
