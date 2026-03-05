//
//  OneRMHelper.swift
//  Muscu
//
//  Formule de Brzycki : 1RM = w * 36 / (37 - r). Utilisé pour stats et suggestion de charge (% 1RM).
//

import Foundation

enum OneRMHelper {
    /// 1RM estimé (Brzycki) : 1RM = w * 36 / (37 - r).
    /// - Returns: nil si reps <= 0 ou reps >= 37 (formule non fiable).
    static func estimatedOneRM(weight: Double, reps: Int) -> Double? {
        guard reps > 0 else { return nil }
        guard reps < 37 else { return weight }
        return weight * 36.0 / Double(37 - reps)
    }

    /// Poids suggéré pour un pourcentage du 1RM (ex: 0.8 = 80%).
    static func weightForPercentage(of oneRM: Double, percentage: Double) -> Double {
        guard oneRM > 0, percentage > 0 else { return 0 }
        return oneRM * percentage / 100.0
    }
}
