//
//  ProgramManager.swift
//  Muscu
//
//  Validation du programme (règles, avertissements).
//

import Foundation
import SwiftData

/// Avertissement émis par le validateur (ex: deux séances jambes consécutives).
struct ScheduleWarning: Identifiable {
    let id = UUID()
    let message: String
    let weekNumber: Int?
    let dayIndex: Int?
}

enum ProgramManager {

    /// Parcourt les semaines/jours du programme et retourne une liste d'avertissements.
    /// Règle exemple : deux jours consécutifs avec bodyFocus == .lower → warning.
    static func validateSchedule(program: TrainingProgram) -> [ScheduleWarning] {
        var warnings: [ScheduleWarning] = []
        let weeks = program.weeks.sorted { $0.weekNumber < $1.weekNumber }

        for week in weeks {
            let days = week.days.sorted { $0.dayIndex < $1.dayIndex }
            for (index, day) in days.enumerated() {
                guard let recipe = day.sessionRecipe else { continue }
                let focus = recipe.bodyFocus

                // Jour suivant dans la même semaine
                if index + 1 < days.count, let nextRecipe = days[index + 1].sessionRecipe {
                    if focus == .lower && nextRecipe.bodyFocus == .lower {
                        warnings.append(ScheduleWarning(
                            message: "Attention : Deux séances jambes consécutives détectées.",
                            weekNumber: week.weekNumber,
                            dayIndex: day.dayIndex
                        ))
                    }
                    if focus == .upper && nextRecipe.bodyFocus == .upper {
                        warnings.append(ScheduleWarning(
                            message: "Attention : Deux séances haut du corps consécutives détectées.",
                            weekNumber: week.weekNumber,
                            dayIndex: day.dayIndex
                        ))
                    }
                }
            }
        }

        return warnings
    }
}
