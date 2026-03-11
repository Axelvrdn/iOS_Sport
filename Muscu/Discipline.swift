//
//  Discipline.swift
//  Muscu
//
//  Rôle : Typage des grandes familles de disciplines pour le profil et le filtrage de programmes.
//

import Foundation

enum Discipline: String, Codable, CaseIterable, Identifiable {
    case combat        // Combat Sports
    case endurance     // Endurance & Cardio
    case racket        // Sports de Raquette
    case outdoor       // Outdoor & Montagne
    case wellness      // Bien-être & Mobilité
    case strength      // Muscu Powerlifting / Bodybuilding
    case street        // Street Lifting / Workout
    case ballSports    // Sports de Ballon : Basket, Volley, Foot

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .combat: return "Sports de combat"
        case .endurance: return "Endurance & Cardio"
        case .racket: return "Sports de raquette"
        case .outdoor: return "Outdoor & Montagne"
        case .wellness: return "Bien-être & Mobilité"
        case .strength: return "Musculation & Force"
        case .street: return "Street Workout"
        case .ballSports: return "Sports de ballon"
        }
    }

    var emoji: String {
        switch self {
        case .combat:     return "🥊"
        case .endurance:  return "🏃‍♂️"
        case .racket:     return "🎾"
        case .outdoor:    return "🏔"
        case .wellness:   return "🧘‍♂️"
        case .strength:   return "🏋️‍♂️"
        case .street:     return "🤸‍♂️"
        case .ballSports: return "🏀"
        }
    }
}

