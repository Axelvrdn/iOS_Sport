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
            sportCategoriesString: "volley,general"
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
        if !existing.isEmpty {
            return Dictionary(uniqueKeysWithValues: existing.map { ($0.name, $0) })
        }

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

        let all = (try? context.fetch(FetchDescriptor<ExerciseMaster>())) ?? []
        return Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })
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

    /// Poids suggéré pour un exercice quand la charge est en % du 1RM (loadStrategy == .percentageOfOneRM).
    /// Utilise ExerciseMaster.estimatedOneRM et le loadValue du SessionExercise (ex: 80 = 80%).
    static func suggestedWeight(for master: ExerciseMaster?, percentage: Double) -> Double? {
        guard let master = master, master.estimatedOneRM > 0, percentage > 0 else { return nil }
        return OneRMHelper.weightForPercentage(of: master.estimatedOneRM, percentage: percentage)
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
