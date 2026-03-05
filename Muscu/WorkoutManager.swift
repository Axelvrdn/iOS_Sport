//
//  WorkoutManager.swift
//  Muscu
//
//  Rôle : Suggestion de prochaine séance (legacy WorkoutProgram/Exercise), streak, Skip / Planifier ; utilisé par SessionRunnerView.
//  Utilisé par : WorkoutView (suggestion séance, streak), SessionRunnerView (program/exercises).
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class WorkoutManager {
    static let shared = WorkoutManager()

    var suggestedProgram: WorkoutProgram?
    var suggestedPhaseIndex: Int = 1
    var suggestedDayIndex: Int = 1
    var suggestedExercises: [Exercise] = []

    /// Série de jours consécutifs avec au moins une séance complétée.
    var currentStreak: Int = 0
    /// Cette semaine : (jours avec séance, objectif 7).
    var weeklyWorkoutDays: (current: Int, goal: Int) = (0, 7)

    private init() {}

    func refreshSuggestion(context: ModelContext) {
        let programFetch = FetchDescriptor<WorkoutProgram>()
        let programs = (try? context.fetch(programFetch)) ?? []
        let profileFetch = FetchDescriptor<UserProfile>()
        let profiles = (try? context.fetch(profileFetch)) ?? []
        let availableDays: [Int] = profiles.first?.availableDays ?? [0, 1, 2, 3, 4, 5, 6]

        guard let program = programs.first else {
            updateStreakAndWeekly(availableDayIndices: availableDays, sessions: [])
            return
        }

        suggestedProgram = program

        let sessionFetch = FetchDescriptor<WorkoutHistorySession>()
        let allSessions = (try? context.fetch(sessionFetch)) ?? []
        let sessions = allSessions
            .filter { $0.programName == program.name && ($0.isCompleted || $0.isSkipped) }
            .sorted { $0.date > $1.date }

        let lastDay = sessions.first?.dayIndex ?? 0
        let nextDay = lastDay >= 7 ? 1 : lastDay + 1

        suggestedDayIndex = nextDay
        suggestedPhaseIndex = 1

        let exerciseFetch = FetchDescriptor<Exercise>()
        let allExercises = (try? context.fetch(exerciseFetch)) ?? []
        suggestedExercises = allExercises
            .filter { ex in
                ex.program == program &&
                ex.phaseIndex == suggestedPhaseIndex &&
                ex.dayIndex == suggestedDayIndex
            }
            .sorted { $0.name < $1.name }

        updateStreakAndWeekly(availableDayIndices: availableDays, sessions: allSessions.filter(\.isCompleted))
    }

    /// Streak = jours consécutifs (en remontant) sans avoir "manqué" un jour disponible. Les jours non disponibles ne cassent pas la série.
    private func updateStreakAndWeekly(availableDayIndices: [Int], sessions: [WorkoutHistorySession]) {
        let calendar = Calendar.current
        let completedDates = Set(sessions.map { calendar.startOfDay(for: $0.date) })
        let today = calendar.startOfDay(for: Date())
        let availableSet = Set(availableDayIndices)

        func weekdayToIndex(_ date: Date) -> Int {
            let w = calendar.component(.weekday, from: date)
            return w == 1 ? 6 : w - 2
        }

        var streak = 0
        var date = today
        while true {
            let dayIndex = weekdayToIndex(date)
            if availableSet.contains(dayIndex) {
                if completedDates.contains(date) {
                    streak += 1
                } else {
                    break
                }
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = prev
        }
        currentStreak = streak

        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) else {
            weeklyWorkoutDays = (0, max(1, availableDayIndices.count))
            return
        }
        var weekDaysWithWorkout = 0
        for dayOffset in 0..<7 {
            guard let d = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { continue }
            if availableSet.contains(weekdayToIndex(d)) && completedDates.contains(d) { weekDaysWithWorkout += 1 }
        }
        weeklyWorkoutDays = (weekDaysWithWorkout, max(1, availableDayIndices.count))
    }

    func markSkipped(context: ModelContext) {
        guard let program = suggestedProgram else { return }
        let session = WorkoutHistorySession(
            date: .now,
            programName: program.name,
            phaseIndex: suggestedPhaseIndex,
            dayIndex: suggestedDayIndex,
            completionPercentage: 0,
            averageRestTimeSeconds: 0,
            totalDurationSeconds: 0,
            isCompleted: false,
            isSkipped: true
        )
        session.program = program
        context.insert(session)
        try? context.save()
        refreshSuggestion(context: context)
    }

    func scheduleInCalendar(at date: Date) async {
        guard let program = suggestedProgram else { return }
        let title = "\(program.name) - Jour \(suggestedDayIndex)"
        let duration: TimeInterval = 60 * 60
        let end = date.addingTimeInterval(duration)
        _ = try? await EventKitManager.shared.createWorkoutEvent(
            title: title,
            startDate: date,
            endDate: end,
            notes: "Séance \(suggestedDayIndex) – \(program.name)"
        )
    }
}

