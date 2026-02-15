//
//  DataController.swift
//  Muscu
//
//  Gère le conteneur SwiftData et le seeding du programme par défaut.
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

    /// Crée le programme "Programme Athlétique" si la base ne contient aucun programme.
    /// 100 % atomique : SessionRecipe + SessionExercise → ExerciseMaster (aucun legacy Exercise).
    static func createDefaultProgram(context: ModelContext) async {
        print("[DataController] createDefaultProgram called")

        let fetch = FetchDescriptor<TrainingProgram>()
        let existing = (try? context.fetch(fetch)) ?? []
        guard existing.isEmpty else {
            print("[DataController] createDefaultProgram: data already exists (\(existing.count) programme(s)), skipping")
            return
        }

        print("[DataController] createDefaultProgram: starting seeding...")

        // 1) Bibliothèque d’exercices (20 ExerciseMaster)
        await seedExerciseLibraryAndSampleSession(context: context)

        let masterFetch = FetchDescriptor<ExerciseMaster>()
        let allMasters = (try? context.fetch(masterFetch)) ?? []
        let mastersByName: [String: ExerciseMaster] = Dictionary(uniqueKeysWithValues: allMasters.map { ($0.name, $0) })

        let program = TrainingProgram(
            name: "Programme Athlétique",
            programDescription: "Programme athlétique 2 mois – Auteur: Betterball_ben",
            sportCategoriesString: "bodybuilding,general"
        )
        context.insert(program)

        let totalWeeks = 8
        let dayCount = 7
        for weekNumber in 1...totalWeeks {
            let week = TrainingWeek(weekNumber: weekNumber)
            week.program = program
            context.insert(week)
            program.weeks.append(week)

            for dayIndex in 0..<dayCount {
                let (isRest, focus, title) = dayConfig(dayIndex: dayIndex)
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

        func week(_ n: Int) -> TrainingWeek? {
            program.weeks.first { $0.weekNumber == n }
        }
        func day(in w: TrainingWeek, _ idx: Int) -> TrainingDay? {
            w.days.first { $0.dayIndex == idx }
        }

        /// Ajoute un SessionExercise à une SessionRecipe en récupérant l’ExerciseMaster par nom.
        func addSessionExercise(
            to recipe: SessionRecipe,
            masterName: String,
            sets: Int,
            reps: String,
            restTime: Int,
            masters: [String: ExerciseMaster]
        ) {
            guard let master = masters[masterName] else { return }
            let se = SessionExercise(
                sets: sets,
                reps: reps,
                restTime: restTime,
                loadStrategy: .fixedWeight,
                loadValue: 0
            )
            context.insert(se)
            se.exercise = master
            se.session = recipe
            recipe.exercises.append(se)
        }

        /// Jours Lower (Phase 1) : recette + exercices depuis la bibliothèque.
        func attachLowerRecipe(to day: TrainingDay) {
            let recipe = SessionRecipe(
                name: day.title,
                goal: .strength,
                bodyFocus: .lower,
                sportCategoriesString: "bodybuilding,general"
            )
            context.insert(recipe)
            recipe.day = day
            day.sessionRecipe = recipe

            let items: [(String, Int, String, Int)] = [
                ("Incline Knee Raises", 3, "10", 30),
                ("Vertical Jump", 3, "7", 75),
                ("Back Squat", 3, "8", 90),
                ("Air Squat", 3, "12", 60),
                ("Lunges", 3, "8", 60),
                ("Romanian Deadlift", 3, "8", 90),
                ("Glute Bridge", 3, "30s", 60),
                ("Calf Raises", 3, "8", 60),
            ]
            for (name, sets, reps, rest) in items {
                addSessionExercise(to: recipe, masterName: name, sets: sets, reps: reps, restTime: rest, masters: mastersByName)
            }
        }

        /// Jours Upper : recette + exercices.
        func attachUpperRecipe(to day: TrainingDay) {
            let recipe = SessionRecipe(
                name: day.title,
                goal: .volume,
                bodyFocus: .upper,
                sportCategoriesString: "bodybuilding,general"
            )
            context.insert(recipe)
            recipe.day = day
            day.sessionRecipe = recipe

            let items: [(String, Int, String, Int)] = [
                ("Bench Press", 3, "10", 90),
                ("Push-Up", 3, "10", 90),
                ("Military Press", 3, "10", 90),
                ("Lat Pulldown", 3, "10", 90),
                ("Barbell Row", 3, "10", 90),
                ("Plank", 3, "30s", 45),
                ("Pallof Press", 3, "30s", 45),
                ("Dead Bug", 3, "8", 45),
            ]
            for (name, sets, reps, rest) in items {
                addSessionExercise(to: recipe, masterName: name, sets: sets, reps: reps, restTime: rest, masters: mastersByName)
            }
        }

        /// Jour Athletic / Plyométrie.
        func attachAthleticRecipe(to day: TrainingDay) {
            let recipe = SessionRecipe(
                name: day.title,
                goal: .technique,
                bodyFocus: .fullBody,
                sportCategoriesString: "bodybuilding,general"
            )
            context.insert(recipe)
            recipe.day = day
            day.sessionRecipe = recipe

            let items: [(String, Int, String, Int)] = [
                ("Sprint 30m", 3, "2", 60),
                ("Lateral Shuffle", 3, "20s", 30),
                ("Vertical Jump", 3, "7", 75),
                ("Burpees", 3, "10", 60),
            ]
            for (name, sets, reps, rest) in items {
                addSessionExercise(to: recipe, masterName: name, sets: sets, reps: reps, restTime: rest, masters: mastersByName)
            }
        }

        /// Jours Lower Phase 2 (semaines 5–8, jour 0).
        func attachLowerPhase2Recipe(to day: TrainingDay) {
            day.title = "Lower Body (Phase 2)"
            let recipe = SessionRecipe(
                name: day.title,
                goal: .strength,
                bodyFocus: .lower,
                sportCategoriesString: "bodybuilding,general"
            )
            context.insert(recipe)
            recipe.day = day
            day.sessionRecipe = recipe

            let items: [(String, Int, String, Int)] = [
                ("Back Squat", 3, "5", 90),
                ("Vertical Jump", 3, "5", 90),
                ("Bulgarian Split Squat", 3, "7", 90),
                ("Lunges", 3, "6", 90),
                ("Glute Bridge", 3, "20s", 90),
                ("Plank", 3, "30s", 60),
            ]
            for (name, sets, reps, rest) in items {
                addSessionExercise(to: recipe, masterName: name, sets: sets, reps: reps, restTime: rest, masters: mastersByName)
            }
        }

        // Remplir chaque semaine
        for weekNumber in 1...totalWeeks {
            guard let w = week(weekNumber) else { continue }
            if let d0 = day(in: w, 0) {
                d0.isRestDay = false
                d0.focusCategory = .lowerBody
                d0.title = "Lower Body"
                if weekNumber >= 5 {
                    attachLowerPhase2Recipe(to: d0)
                } else {
                    attachLowerRecipe(to: d0)
                }
            }
            if let d1 = day(in: w, 1) {
                d1.isRestDay = false
                d1.focusCategory = .upperBody
                d1.title = "Upper Body"
                attachUpperRecipe(to: d1)
            }
            if let d2 = day(in: w, 2) {
                d2.isRestDay = false
                d2.focusCategory = .plyometrics
                d2.title = "Athletic / Plyometrics"
                attachAthleticRecipe(to: d2)
            }
            if let d3 = day(in: w, 3) {
                d3.isRestDay = true
                d3.focusCategory = .none
                d3.title = "Repos"
            }
            if let d4 = day(in: w, 4) {
                d4.isRestDay = false
                d4.focusCategory = .lowerBody
                d4.title = "Lower Body"
                attachLowerRecipe(to: d4)
            }
            if let d5 = day(in: w, 5) {
                d5.isRestDay = false
                d5.focusCategory = .upperBody
                d5.title = "Upper Body"
                attachUpperRecipe(to: d5)
            }
            if let d6 = day(in: w, 6) {
                d6.isRestDay = true
                d6.focusCategory = .none
                d6.title = "Repos"
            }
        }

        do {
            try context.save()
            print("[DataController] createDefaultProgram: seeding completed")
        } catch {
            print("[DataController] createDefaultProgram error: \(error)")
        }
    }

    /// Crée la bibliothèque ExerciseMaster (20 exercices courants) pour l’éditeur.
    /// Ne crée pas de SessionRecipe ; le programme par défaut les attache dans createDefaultProgram.
    static func seedExerciseLibraryAndSampleSession(context: ModelContext) async {
        let fetch = FetchDescriptor<ExerciseMaster>()
        let existing = (try? context.fetch(fetch)) ?? []
        guard existing.isEmpty else { return }

        let masters: [(name: String, asset: String, muscles: String, rest: Int)] = [
            ("Back Squat", "figure.strengthtraining.traditional", "legs", 90),
            ("Air Squat", "figure.strengthtraining.traditional", "legs", 60),
            ("Lunges", "figure.strengthtraining.traditional", "legs", 60),
            ("Romanian Deadlift", "figure.strengthtraining.traditional", "back,legs", 90),
            ("Glute Bridge", "figure.strengthtraining.traditional", "legs", 60),
            ("Calf Raises", "figure.strengthtraining.traditional", "legs", 60),
            ("Bench Press", "figure.strengthtraining.traditional", "chest", 90),
            ("Push-Up", "figure.strengthtraining.traditional", "chest,arms", 90),
            ("Military Press", "figure.strengthtraining.traditional", "shoulders", 90),
            ("Barbell Row", "figure.strengthtraining.traditional", "back", 90),
            ("Lat Pulldown", "figure.strengthtraining.traditional", "back", 90),
            ("Plank", "figure.core.training", "core", 45),
            ("Dead Bug", "figure.core.training", "core", 45),
            ("Sprint 30m", "figure.run", "legs,fullBody", 60),
            ("Lateral Shuffle", "figure.run", "legs", 30),
            ("Vertical Jump", "figure.jumprope", "legs", 75),
            ("Burpees", "figure.highintensity.intervaltraining", "fullBody", 60),
            ("Bulgarian Split Squat", "figure.strengthtraining.traditional", "legs", 90),
            ("Pallof Press", "figure.strengthtraining.traditional", "core", 45),
            ("Incline Knee Raises", "figure.core.training", "core", 30),
        ]

        for m in masters {
            let master = ExerciseMaster(
                name: m.name,
                visualAsset: m.asset,
                videoUrl: nil,
                exerciseDescription: "Exercice : \(m.name)",
                musclesTargetedString: m.muscles,
                defaultRestTime: m.rest
            )
            context.insert(master)
        }

        do {
            try context.save()
        } catch {
            print("Erreur seeding ExerciseMaster: \(error)")
        }
    }

    private static func dayConfig(dayIndex: Int) -> (Bool, FocusCategory, String) {
        switch dayIndex {
        case 0: return (false, .lowerBody, "Lower Body")
        case 1: return (false, .upperBody, "Upper Body")
        case 2: return (false, .plyometrics, "Athletic")
        case 3: return (true, .none, "Repos")
        case 4: return (false, .lowerBody, "Lower Body")
        case 5: return (false, .upperBody, "Upper Body")
        case 6: return (true, .none, "Repos")
        default: return (true, .none, "Repos")
        }
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
}
