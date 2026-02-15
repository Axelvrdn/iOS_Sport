//
//  Models.swift
//  Muscu
//
//  Core SwiftData models and supporting types for the fitness app.
//

import Foundation
import SwiftData

// MARK: - Supporting Enums

enum PhysiqueGoal: String, Codable, CaseIterable {
    case cut
    case maintain
    case bulk
}

enum TrainingStyle: Codable {
    case bodybuilding
    case marathon
    case hybrid
    case specificSport(SpecificSport)
    
    // Implémentation manuelle de Codable pour éviter les problèmes de thread-safety avec SwiftData
    enum CodingKeys: String, CodingKey {
        case type
        case sport
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "bodybuilding":
            self = .bodybuilding
        case "marathon":
            self = .marathon
        case "hybrid":
            self = .hybrid
        case "specificSport":
            let sport = try container.decode(SpecificSport.self, forKey: .sport)
            self = .specificSport(sport)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown TrainingStyle type: \(type)")
        }
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .bodybuilding:
            try container.encode("bodybuilding", forKey: .type)
        case .marathon:
            try container.encode("marathon", forKey: .type)
        case .hybrid:
            try container.encode("hybrid", forKey: .type)
        case .specificSport(let sport):
            try container.encode("specificSport", forKey: .type)
            try container.encode(sport, forKey: .sport)
        }
    }
}

enum SpecificSport: String, Codable, CaseIterable {
    case boxing
    case volley
    case basket
}

enum InjurySensitivity: String, Codable, CaseIterable {
    case low
    case medium
    case high
}

// MARK: - FocusCategory (Program Builder)

enum FocusCategory: String, Codable, CaseIterable {
    case lowerBody
    case upperBody
    case plyometrics
    case push
    case pull
    case legs
    case cardio
    case hybrid
    case none
}

// MARK: - Atomic Training System Enums

enum MuscleGroup: String, Codable, CaseIterable {
    case chest
    case back
    case legs
    case shoulders
    case arms
    case core
    case fullBody
}

enum LoadStrategy: String, Codable, CaseIterable {
    case fixedWeight
    case percentageOfOneRM
    case rpe
}

enum SessionGoal: String, Codable, CaseIterable {
    case volume
    case strength
    case technique
    case endurance
    case rehab
}

enum BodyFocus: String, Codable, CaseIterable {
    case upper
    case lower
    case push
    case pull
    case fullBody
}

enum SportCategory: String, Codable, CaseIterable {
    case bodybuilding
    case volley
    case basket
    case running
    case boxing
    case general
}

// MARK: - UserProfile

@Model
final class UserProfile {
    var age: Int
    var weight: Double
    var physiqueGoal: PhysiqueGoal
    var trainingStyle: TrainingStyle
    var injuryHistory: String
    var injurySensitivity: InjurySensitivity
    var sessionsPerWeek: Int
    var hoursPerSession: Double
    var sportsHistory: String
    var currentOtherSports: String
    var weightGoal: Double
    /// 0.0 (très doux) à 1.0 (très strict)
    var strictnessLevel: Double
    /// Représentation sérialisée des jours / créneaux disponibles (legacy)
    var availabilityJSON: String
    /// Jours disponibles pour l'entraînement (0=Lun … 6=Dim), stocké "0,1,2,3,4,5,6"
    var availableDaysString: String

    @Relationship(deleteRule: .cascade)
    var workoutPrograms: [WorkoutProgram] = []

    /// Programme actif (modèle atomique TrainingProgram) — source de vérité pour l’affichage.
    var activeTrainingProgram: TrainingProgram?

    init(
        age: Int = 0,
        weight: Double = 0,
        physiqueGoal: PhysiqueGoal = .maintain,
        trainingStyle: TrainingStyle = .bodybuilding,
        injuryHistory: String = "",
        injurySensitivity: InjurySensitivity = .medium,
        sessionsPerWeek: Int = 3,
        hoursPerSession: Double = 1.0,
        sportsHistory: String = "",
        currentOtherSports: String = "",
        weightGoal: Double = 0,
        strictnessLevel: Double = 0.5,
        availabilityJSON: String = "{}",
        availableDaysString: String = "0,1,2,3,4,5,6"
    ) {
        self.age = age
        self.weight = weight
        self.physiqueGoal = physiqueGoal
        self.trainingStyle = trainingStyle
        self.injuryHistory = injuryHistory
        self.injurySensitivity = injurySensitivity
        self.sessionsPerWeek = sessionsPerWeek
        self.hoursPerSession = hoursPerSession
        self.sportsHistory = sportsHistory
        self.currentOtherSports = currentOtherSports
        self.weightGoal = weightGoal
        self.strictnessLevel = strictnessLevel
        self.availabilityJSON = availabilityJSON
        self.availableDaysString = availableDaysString
    }
}

// MARK: - UserProfile available days helpers

extension UserProfile {
    /// Indices des jours disponibles (0 = Lundi … 6 = Dimanche). Source de vérité pour planification et streak.
    var availableDays: [Int] {
        get {
            parseAvailableDaysString(availableDaysString)
        }
        set {
            availableDaysString = newValue.sorted().map(String.init).joined(separator: ",")
        }
    }
}

private func parseAvailableDaysString(_ s: String) -> [Int] {
    let parts = s.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    return parts.filter { (0...6).contains($0) }
}

// MARK: - WorkoutProgram

@Model
final class WorkoutProgram {
    var name: String
    var difficulty: String
    var type: String
    /// Nom de l’auteur / créateur du programme
    var author: String
    /// Nombre total de phases (mois) dans le programme
    var phaseCount: Int

    @Relationship(deleteRule: .cascade)
    var exercises: [Exercise] = []

    @Relationship(deleteRule: .cascade)
    var sessions: [WorkoutHistorySession] = []

    @Relationship(inverse: \UserProfile.workoutPrograms)
    var owner: UserProfile?

    init(
        name: String,
        difficulty: String,
        type: String,
        author: String = "",
        phaseCount: Int = 1
    ) {
        self.name = name
        self.difficulty = difficulty
        self.type = type
        self.author = author
        self.phaseCount = phaseCount
    }
}

// MARK: - Exercise (support type for WorkoutProgram)

@Model
final class Exercise {
    var name: String
    var targetMuscleGroup: String
    /// Description libre du schéma séries/répétitions, ex: "3x20s", "3x5+5"
    var setsRepsDescription: String
    /// Temps de repos en secondes entre les séries
    var restSeconds: Int
    /// Indique si l’exercice nécessite du matériel (haltères, barre, machine…)
    var equipmentRequired: Bool
    /// Marqueur pour les exercices bonus
    var isBonus: Bool
    /// Phase (mois) du programme à laquelle appartient l’exercice (1 = Phase 1, 2 = Phase 2…)
    var phaseIndex: Int
    /// Index du jour dans la semaine (1 = Day 1, 2 = Day 2, …)
    var dayIndex: Int
    /// Nom lisible du jour, ex: "Day 1 (Lower Body)"
    var dayName: String
    /// Catégorie principale du jour (Lower / Upper / Athletic)
    var dayFocus: String
    /// URL de la vidéo d'exemple (YouTube, etc.)
    var videoUrl: String?

    /// Exercice alternatif sans matériel (Bodyweight), si disponible
    @Relationship
    var alternativeExercise: Exercise?

    @Relationship(inverse: \WorkoutProgram.exercises)
    var program: WorkoutProgram?

    /// Inverse of TrainingDay.exercises (framework-style builder).
    @Relationship(inverse: \TrainingDay.exercises)
    var trainingDay: TrainingDay?

    init(
        name: String,
        targetMuscleGroup: String,
        setsRepsDescription: String,
        restSeconds: Int,
        equipmentRequired: Bool,
        isBonus: Bool = false,
        phaseIndex: Int,
        dayIndex: Int,
        dayName: String,
        dayFocus: String,
        videoUrl: String? = nil,
        alternativeExercise: Exercise? = nil
    ) {
        self.name = name
        self.targetMuscleGroup = targetMuscleGroup
        self.setsRepsDescription = setsRepsDescription
        self.restSeconds = restSeconds
        self.equipmentRequired = equipmentRequired
        self.isBonus = isBonus
        self.phaseIndex = phaseIndex
        self.dayIndex = dayIndex
        self.dayName = dayName
        self.dayFocus = dayFocus
        self.videoUrl = videoUrl
        self.alternativeExercise = alternativeExercise
    }
}

// MARK: - DailyLog

@Model
final class DailyLog {
    var date: Date
    /// 0–10, subjectif
    var sleepQuality: Int
    var steps: Int
    /// 0–10
    var sorenessLevel: Int
    /// 0–10
    var mood: Int

    init(
        date: Date = .now,
        sleepQuality: Int = 5,
        steps: Int = 0,
        sorenessLevel: Int = 0,
        mood: Int = 5
    ) {
        self.date = date
        self.sleepQuality = sleepQuality
        self.steps = steps
        self.sorenessLevel = sorenessLevel
        self.mood = mood
    }
}

// MARK: - WorkoutHistorySession (historique: adherence, completion)

@Model
final class WorkoutHistorySession {
    var date: Date
    var programName: String
    /// Phase (mois) du programme
    var phaseIndex: Int
    /// Jour dans la semaine (1 = Day 1, …)
    var dayIndex: Int
    /// Pourcentage de complétion (0-100)
    var completionPercentage: Int
    /// Temps de repos moyen en secondes
    var averageRestTimeSeconds: Int
    /// Durée totale de la séance en secondes
    var totalDurationSeconds: Int
    /// Indique si la séance a été complétée
    var isCompleted: Bool
    /// Indique si la séance a été explicitement skippée
    var isSkipped: Bool

    @Relationship(inverse: \WorkoutProgram.sessions)
    var program: WorkoutProgram?

    init(
        date: Date = .now,
        programName: String = "",
        phaseIndex: Int = 1,
        dayIndex: Int = 1,
        completionPercentage: Int = 0,
        averageRestTimeSeconds: Int = 60,
        totalDurationSeconds: Int = 0,
        isCompleted: Bool = false,
        isSkipped: Bool = false
    ) {
        self.date = date
        self.programName = programName
        self.phaseIndex = phaseIndex
        self.dayIndex = dayIndex
        self.completionPercentage = completionPercentage
        self.averageRestTimeSeconds = averageRestTimeSeconds
        self.totalDurationSeconds = totalDurationSeconds
        self.isCompleted = isCompleted
        self.isSkipped = isSkipped
    }
}

// MARK: - TrainingProgram / TrainingWeek / TrainingDay (Framework-style builder)
// Hierarchy: Program → Weeks → Days → SessionRecipe (optional) → SessionExercise → ExerciseMaster

@Model
final class TrainingProgram {
    var name: String
    var programDescription: String
    /// Catégories sportives du programme (stocké "bodybuilding,volley")
    var sportCategoriesString: String
    /// Règles de validation (ex: "No double leg days")
    var validationRules: String?

    @Relationship(deleteRule: .cascade)
    var weeks: [TrainingWeek] = []

    init(name: String, programDescription: String = "", sportCategoriesString: String = "", validationRules: String? = nil) {
        self.name = name
        self.programDescription = programDescription
        self.sportCategoriesString = sportCategoriesString
        self.validationRules = validationRules
    }
}

extension TrainingProgram {
    var sportCategories: [SportCategory] {
        get { parseSportCategories(sportCategoriesString) }
        set { sportCategoriesString = newValue.map(\.rawValue).joined(separator: ",") }
    }
}

@Model
final class TrainingWeek {
    var weekNumber: Int

    /// Dynamic: a week can have any number of days (e.g. 2, 5, 7).
    @Relationship(deleteRule: .cascade)
    var days: [TrainingDay] = []

    @Relationship(inverse: \TrainingProgram.weeks)
    var program: TrainingProgram?

    init(weekNumber: Int) {
        self.weekNumber = weekNumber
    }
}

@Model
final class TrainingDay {
    /// Position in the week (0-based). Order is determined by array order; index is for display/sort.
    var dayIndex: Int
    var isRestDay: Bool
    var focusCategory: FocusCategory
    var title: String

    /// Exercises directly on the day (legacy / fallback).
    @Relationship(deleteRule: .cascade)
    var exercises: [Exercise] = []

    /// Recipe (session template) for this day — uses ExerciseMaster + SessionExercise.
    /// Inverse maintenu par SessionRecipe.day (évite référence circulaire du macro).
    var sessionRecipe: SessionRecipe?

    @Relationship(inverse: \TrainingWeek.days)
    var week: TrainingWeek?

    init(dayIndex: Int, isRestDay: Bool = false, focusCategory: FocusCategory = .none, title: String = "") {
        self.dayIndex = dayIndex
        self.isRestDay = isRestDay
        self.focusCategory = focusCategory
        self.title = title
    }
}

// MARK: - ExerciseMaster (Library Item)

@Model
final class ExerciseMaster {
    var name: String
    var visualAsset: String
    var videoUrl: String?
    var exerciseDescription: String
    /// Stocké "chest,legs" pour SwiftData
    var musclesTargetedString: String
    var defaultRestTime: Int

    init(
        name: String,
        visualAsset: String = "figure.strengthtraining.traditional",
        videoUrl: String? = nil,
        exerciseDescription: String = "",
        musclesTargetedString: String = "",
        defaultRestTime: Int = 60
    ) {
        self.name = name
        self.visualAsset = visualAsset
        self.videoUrl = videoUrl
        self.exerciseDescription = exerciseDescription
        self.musclesTargetedString = musclesTargetedString
        self.defaultRestTime = defaultRestTime
    }
}

extension ExerciseMaster {
    var musclesTargeted: [MuscleGroup] {
        get { parseMuscleGroups(musclesTargetedString) }
        set { musclesTargetedString = newValue.map(\.rawValue).joined(separator: ",") }
    }
}

// MARK: - SessionExercise (Configuration: link Session ↔ Master)

@Model
final class SessionExercise {
    var sets: Int
    var reps: String
    var restTime: Int
    var loadStrategy: LoadStrategy
    var loadValue: Double

    @Relationship
    var exercise: ExerciseMaster?
    @Relationship(inverse: \SessionRecipe.exercises)
    var session: SessionRecipe?

    init(
        sets: Int = 3,
        reps: String = "10",
        restTime: Int = 60,
        loadStrategy: LoadStrategy = .fixedWeight,
        loadValue: Double = 0
    ) {
        self.sets = sets
        self.reps = reps
        self.restTime = restTime
        self.loadStrategy = loadStrategy
        self.loadValue = loadValue
    }
}

// MARK: - SessionRecipe (The Recipe: name, goal, bodyFocus, ordered SessionExercises)

@Model
final class SessionRecipe {
    var name: String
    var goal: SessionGoal
    var bodyFocus: BodyFocus
    var sportCategoriesString: String

    @Relationship(deleteRule: .cascade)
    var exercises: [SessionExercise] = []

    /// Référence vers le jour ; l’inverse TrainingDay.sessionRecipe est maintenu par SwiftData.
    @Relationship(inverse: \TrainingDay.sessionRecipe)
    var day: TrainingDay?

    init(
        name: String,
        goal: SessionGoal = .volume,
        bodyFocus: BodyFocus = .fullBody,
        sportCategoriesString: String = ""
    ) {
        self.name = name
        self.goal = goal
        self.bodyFocus = bodyFocus
        self.sportCategoriesString = sportCategoriesString
    }
}

extension SessionRecipe {
    var sportCategories: [SportCategory] {
        get { parseSportCategories(sportCategoriesString) }
        set { sportCategoriesString = newValue.map(\.rawValue).joined(separator: ",") }
    }
}

// MARK: - Helpers for stored strings

private func parseMuscleGroups(_ s: String) -> [MuscleGroup] {
    s.split(separator: ",").compactMap { MuscleGroup(rawValue: String($0.trimmingCharacters(in: .whitespaces))) }
}

private func parseSportCategories(_ s: String) -> [SportCategory] {
    s.split(separator: ",").compactMap { SportCategory(rawValue: String($0.trimmingCharacters(in: .whitespaces))) }
}

// MARK: - WorkoutSession (legacy: template for WorkoutProgram / other flows)

@Model
final class WorkoutSession {
    var title: String
    var notes: String

    @Relationship(deleteRule: .cascade)
    var exercises: [Exercise] = []

    init(title: String, notes: String = "") {
        self.title = title
        self.notes = notes
    }
}

// MARK: - WorkoutLog (log de chaque série)

@Model
final class WorkoutLog {
    var date: Date
    var programName: String
    var phaseIndex: Int
    var dayIndex: Int
    var exerciseName: String
    var setIndex: Int
    var targetReps: String
    var targetWeight: String
    var actualReps: Int
    var actualWeight: Double

    init(
        date: Date = .now,
        programName: String,
        phaseIndex: Int,
        dayIndex: Int,
        exerciseName: String,
        setIndex: Int,
        targetReps: String,
        targetWeight: String = "",
        actualReps: Int,
        actualWeight: Double
    ) {
        self.date = date
        self.programName = programName
        self.phaseIndex = phaseIndex
        self.dayIndex = dayIndex
        self.exerciseName = exerciseName
        self.setIndex = setIndex
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.actualReps = actualReps
        self.actualWeight = actualWeight
    }
}

