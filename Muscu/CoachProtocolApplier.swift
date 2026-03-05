//
//  CoachProtocolApplier.swift
//  Muscu
//
//  Applique les protocoles de santé (Deload, Full Rest, Blessure) sur le programme actif.
//

import Foundation
import SwiftData

enum CoachProtocolApplier {

    /// BodyPart → MuscleGroup à éviter pour les alternatives "safe".
    private static let injuryZoneToMuscleGroup: [BodyPart: MuscleGroup] = [
        .shoulder: .shoulders,
        .knee: .legs,
        .ankle: .legs,
        .hip: .legs,
        .back: .back,
        .wrist: .arms,
        .neck: .shoulders
    ]

    /// Nombre d’exercices qui seraient modifiés (pour affichage dans la carte de protocole). Ne modifie pas les données.
    static func previewModificationCount(protocol kind: CoachProtocol, program: TrainingProgram?, context: ModelContext?) -> Int? {
        guard let program = program, context != nil else { return nil }
        guard let recipe = firstSessionRecipe(in: program) else { return nil }
        switch kind {
        case .deload:
            return recipe.exercises.count
        case .fullRest:
            return nil
        case .injury(let zone):
            if zone == .shoulder {
                return recipe.exercises.filter { se in
                    guard let m = se.exercise else { return false }
                    let n = m.name.lowercased()
                    return n.contains("développé") || n.contains("push")
                }.count
            }
            let avoidGroup = zone.flatMap { injuryZoneToMuscleGroup[$0] }
            guard let group = avoidGroup else { return 0 }
            return recipe.exercises.filter { se in
                guard let m = se.exercise else { return false }
                return m.musclesTargeted.contains(group)
            }.count
        }
    }

    /// Retourne la première SessionRecipe du programme (séance active).
    static func firstSessionRecipe(in program: TrainingProgram) -> SessionRecipe? {
        for week in program.weeks {
            for day in week.days {
                if let recipe = day.sessionRecipe { return recipe }
            }
        }
        return nil
    }

    /// Deload : divise par 2 les séries et les reps de chaque exercice de la séance active.
    static func applyDeload(program: TrainingProgram, context: ModelContext) throws -> Int {
        guard let recipe = firstSessionRecipe(in: program) else { return 0 }
        var count = 0
        for se in recipe.exercises {
            let newSets = max(1, se.sets / 2)
            if newSets != se.sets {
                se.sets = newSets
                count += 1
            }
            let newReps = halveRepsString(se.reps)
            if newReps != se.reps {
                se.reps = newReps
                count += 1
            }
        }
        try context.save()
        return count
    }

    private static func halveRepsString(_ reps: String) -> String {
        let t = reps.trimmingCharacters(in: .whitespaces)
        if let n = Int(t) {
            return "\(max(1, n / 2))"
        }
        if let idx = t.firstIndex(of: "x"), let n = Int(t[t.index(after: idx)...].trimmingCharacters(in: .whitespaces)) {
            let prefix = String(t[..<idx]).trimmingCharacters(in: .whitespaces)
            let half = max(1, n / 2)
            return prefix.isEmpty ? "\(half)" : "\(prefix)x\(half)"
        }
        return reps
    }

    /// Full Rest : insère une semaine de repos (7 jours isRestDay) à la fin du programme.
    static func applyFullRest(program: TrainingProgram, context: ModelContext) throws {
        let maxWeekNumber = program.weeks.map(\.weekNumber).max() ?? 0
        let restWeek = TrainingWeek(weekNumber: maxWeekNumber + 1)
        restWeek.program = program
        context.insert(restWeek)
        program.weeks.append(restWeek)
        for dayIndex in 0..<7 {
            let day = TrainingDay(dayIndex: dayIndex, isRestDay: true, focusCategory: .none, title: "Repos")
            day.week = restWeek
            context.insert(day)
            restWeek.days.append(day)
        }
        try context.save()
    }

    /// Blessure : remplace les exercices ciblant la zone par une alternative safe.
    /// Pour l’épaule : remplace les exercices dont le nom contient "Développé" ou "Push" par du tirage (dos) ou bas du corps (legs).
    static func applyInjury(zone: BodyPart?, program: TrainingProgram, context: ModelContext) throws -> Int {
        guard let recipe = firstSessionRecipe(in: program) else { return 0 }
        let allMasters = (try? context.fetch(FetchDescriptor<ExerciseMaster>())) ?? []

        if zone == .shoulder {
            return try applyInjuryShoulder(recipe: recipe, allMasters: allMasters, context: context)
        }

        let avoidGroup = zone.flatMap { injuryZoneToMuscleGroup[$0] }
        let pool: [ExerciseMaster]
        if let group = avoidGroup {
            pool = allMasters.filter { !$0.musclesTargeted.contains(group) }
        } else {
            pool = allMasters
        }
        guard let fallback = pool.first else { return 0 }
        var count = 0
        for se in recipe.exercises {
            guard let master = se.exercise else { continue }
            let targetsZone = avoidGroup.map { master.musclesTargeted.contains($0) } ?? false
            if targetsZone {
                se.exercise = fallback
                count += 1
            }
        }
        try context.save()
        return count
    }

    /// Épaule : exercices dont le nom contient "Développé" ou "Push" → remplacés par tirage (dos) ou bas du corps (legs).
    private static func applyInjuryShoulder(recipe: SessionRecipe, allMasters: [ExerciseMaster], context: ModelContext) throws -> Int {
        let pushKeywords = ["développé", "push"]
        let replacementPool = allMasters.filter { master in
            let hasBack = master.musclesTargeted.contains(.back)
            let hasLegs = master.musclesTargeted.contains(.legs)
            let noShoulders = !master.musclesTargeted.contains(.shoulders)
            return (hasBack || hasLegs) && noShoulders
        }
        guard !replacementPool.isEmpty else { return 0 }
        var count = 0
        var poolIndex = 0
        for se in recipe.exercises {
            guard let master = se.exercise else { continue }
            let name = master.name.lowercased()
            let isPush = pushKeywords.contains { name.contains($0) }
            if isPush {
                se.exercise = replacementPool[poolIndex % replacementPool.count]
                poolIndex += 1
                count += 1
            }
        }
        try context.save()
        return count
    }

    /// Suggestion pour le message IA : "On remplace [X] par [Y] pour aujourd'hui ?"
    static func suggestedReplacementMessage(zone: BodyPart, program: TrainingProgram, context: ModelContext?) -> (fromName: String, toName: String)? {
        guard let context = context, let recipe = firstSessionRecipe(in: program) else { return nil }
        let allMasters = (try? context.fetch(FetchDescriptor<ExerciseMaster>())) ?? []
        guard !allMasters.isEmpty else { return nil }

        switch zone {
        case .back:
            guard let toReplace = recipe.exercises.first(where: { $0.exercise?.musclesTargeted.contains(.back) == true }),
                  let from = toReplace.exercise else { return nil }
            let alternative = allMasters.first { $0.musclesTargeted.contains(.legs) && !$0.musclesTargeted.contains(.back) }
                ?? allMasters.first { !$0.musclesTargeted.contains(.back) }
            guard let to = alternative else { return nil }
            return (from.name, to.name)
        case .knee:
            guard let toReplace = recipe.exercises.first(where: { $0.exercise?.musclesTargeted.contains(.legs) == true }),
                  let from = toReplace.exercise else { return nil }
            let alternative = allMasters.first { $0.musclesTargeted.contains(.back) }
                ?? allMasters.first { !$0.musclesTargeted.contains(.legs) }
            guard let to = alternative else { return nil }
            return (from.name, to.name)
        case .shoulder:
            guard let toReplace = recipe.exercises.first(where: { se in
                guard let m = se.exercise else { return false }
                let n = m.name.lowercased()
                return n.contains("développé") || n.contains("push")
            }), let from = toReplace.exercise else { return nil }
            let alternative = allMasters.first { ($0.musclesTargeted.contains(.back) || $0.musclesTargeted.contains(.legs)) && !$0.musclesTargeted.contains(.shoulders) }
            guard let to = alternative else { return nil }
            return (from.name, to.name)
        default:
            guard let group = injuryZoneToMuscleGroup[zone],
                  let toReplace = recipe.exercises.first(where: { $0.exercise?.musclesTargeted.contains(group) == true }),
                  let from = toReplace.exercise else { return nil }
            let alternative = allMasters.first { !$0.musclesTargeted.contains(group) }
            guard let to = alternative else { return nil }
            return (from.name, to.name)
        }
    }
}
