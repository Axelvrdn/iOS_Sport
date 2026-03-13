//
//  FatigueEngine.swift
//  Muscu
//
//  Rôle : Calcul de la fatigue hebdomadaire et détection de conflits pour l’athlète hybride.
//

import Foundation
import SwiftData

/// Tags de stress extraits de la description des exercices (hashtags).
enum StressTag: String {
    case shoulderStress = "#ShoulderStress"
    case kneeStress = "#KneeStress"
    case cnsLoad = "#CNSLoad"
}

struct FatigueEngine {

    /// Retourne les tags de stress présents dans la description d'un ExerciseMaster.
    static func tags(for master: ExerciseMaster) -> Set<StressTag> {
        let desc = master.exerciseDescription
        var result = Set<StressTag>()
        for tag in [StressTag.shoulderStress, .kneeStress, .cnsLoad] {
            if desc.localizedCaseInsensitiveContains(tag.rawValue) {
                result.insert(tag)
            }
        }
        return result
    }

    /// Facteur d'impact global à partir des tags.
    static func impactFactor(for tags: Set<StressTag>) -> Double {
        var factor: Double = 1.0
        if tags.contains(.cnsLoad) {
            factor += 0.7
        }
        if tags.contains(.shoulderStress) {
            factor += 0.3
        }
        if tags.contains(.kneeStress) {
            factor += 0.3
        }
        return factor
    }

    /// Calcule un score de fatigue hebdomadaire pour un programme (semaine 1) selon
    /// TotalScore = Σ (Intensity × Volume × ImpactFactor).
    static func weeklyFatigueScore(for program: TrainingProgram) -> Double {
        guard let week = program.weeks.first else { return 0 }

        var total: Double = 0
        for day in week.days {
            guard let recipe = day.sessionRecipe else { continue }
            for se in recipe.exercises {
                guard let master = se.exercise else { continue }
                let tags = tags(for: master)
                let impact = impactFactor(for: tags)
                let intensity = intensityFor(sessionExercise: se, tags: tags)
                let volume = volumeFor(sessionExercise: se)
                total += intensity * volume * impact
            }
        }
        return total
    }

    private static func intensityFor(sessionExercise se: SessionExercise, tags: Set<StressTag>) -> Double {
        var base: Double = 1.0
        if tags.contains(.cnsLoad) { base += 0.5 }
        switch se.loadStrategy {
        case .fixedWeight:
            base += min(se.loadValue / 100.0, 1.0)
        case .percentageOfOneRM:
            base += min(se.loadValue / 100.0, 1.0)
        case .rpe:
            base += min(se.loadValue / 10.0, 1.0)
        }
        return base
    }

    private static func volumeFor(sessionExercise se: SessionExercise) -> Double {
        let sets = Double(se.sets)
        // On essaie d'interpréter les reps comme un entier si possible.
        if let repsInt = Int(se.reps) {
            return sets * Double(repsInt)
        } else {
            // Pour "MAX", "30s", etc., on approxime.
            return sets * 8.0
        }
    }

    // MARK: - Conflits & Deload

    /// Vrai si l'utilisateur a choisi au moins 2 disciplines considérées comme "High Impact".
    static func hasHighImpactCombo(profile: UserProfile) -> Bool {
        let highImpact: Set<Discipline> = [.combat, .ballSports, .street]
        let selected = profile.selectedDisciplines
        let intersection = selected.intersection(highImpact)
        return intersection.count >= 2
    }

    /// Indique si une semaine donnée devrait être en Deload automatique (toutes les 4 semaines en combo high impact).
    static func shouldForceDeload(forWeekNumber week: Int, profile: UserProfile) -> Bool {
        guard hasHighImpactCombo(profile: profile) else { return false }
        return week > 0 && (week % 4 == 0)
    }

    /// Détecte un conflit dans un programme : séance de sauts (Volley/plyométrie) le même jour qu'un sparring combat.
    /// Retourne les jours concernés pour que l’UI propose un décalage de 24 h.
    static func conflictingJumpAndSparringDays(in program: TrainingProgram) -> [TrainingDay] {
        guard let week = program.weeks.first else { return [] }
        return week.days.filter { day in
            let title = day.title.lowercased()
            let isJumpDay = title.contains("saut") || title.contains("plyo") || title.contains("jump")
            let isSparringDay = title.contains("sparring") || title.contains("combat") || title.contains("sac")
            return isJumpDay && isSparringDay
        }
    }
}

