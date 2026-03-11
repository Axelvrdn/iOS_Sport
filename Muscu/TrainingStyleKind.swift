import Foundation

/// Représentation UI du `TrainingStyle` (utilisée dans l'onboarding).
enum TrainingStyleKind: String, CaseIterable, Identifiable {
    case bodybuilding
    case marathon
    case hybrid
    case specificSport

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bodybuilding: return "Musculation"
        case .marathon: return "Endurance"
        case .hybrid: return "Hybride"
        case .specificSport: return "Sport spécifique"
        }
    }

    var iconName: String {
        switch self {
        case .bodybuilding: return "dumbbell.fill"
        case .marathon: return "figure.run"
        case .hybrid: return "figure.mixed.cardio"
        case .specificSport: return "sportscourt.fill"
        }
    }

    func toTrainingStyle(specificSport: SpecificSport = .volley) -> TrainingStyle {
        switch self {
        case .bodybuilding: return .bodybuilding
        case .marathon: return .marathon
        case .hybrid: return .hybrid
        case .specificSport: return .specificSport(specificSport)
        }
    }
}

