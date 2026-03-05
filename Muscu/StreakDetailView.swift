//
//  StreakDetailView.swift
//  Muscu
//
//  Rôle : Détail du streak (série de jours, historique semaines, séances manquées, jours engagés).
//  Utilisé par : WorkoutView (NavigationLink depuis StreakCardView).
//

import SwiftUI
import SwiftData

struct StreakDetailView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \WorkoutHistorySession.date, order: .reverse) private var allSessions: [WorkoutHistorySession]

    private var profile: UserProfile? { profiles.first }
    private var availableDays: [Int] { profile?.availableDays ?? [0, 1, 2, 3, 4, 5, 6] }
    private var completedSessions: [WorkoutHistorySession] { allSessions.filter(\.isCompleted) }

    private let dayLabels = ["L", "M", "M", "J", "V", "S", "D"]

    private var currentStreak: Int { computeStreak() }
    private var missedWorkoutsCount: Int { computeMissedWorkouts() }
    private var weeklyHistory: [(weekStart: Date, completed: Int, goal: Int)] { computeWeeklyHistory() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                committedDaysSection
                metricsSection
                historySection
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Ma série")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        HStack(spacing: 20) {
            Image(systemName: "flame.fill")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .red],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
            VStack(alignment: .leading, spacing: 4) {
                Text("\(currentStreak) jours")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text(currentStreak > 0 ? "Continue comme ça !" : "Lance une séance pour démarrer ta série")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .dashboardCard()
    }

    private var committedDaysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jours engagés (Profil)")
                .font(.headline.bold())
            Text("Tu as défini ces jours comme disponibles pour l'entraînement. La série ne compte que ces jours.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(0..<7, id: \.self) { index in
                    let isAvailable = availableDays.contains(index)
                    Text(dayLabels[index])
                        .font(.caption.bold())
                        .frame(width: 36, height: 36)
                        .background(isAvailable ? Color.accentColor.opacity(0.25) : Color(.tertiarySystemFill))
                        .foregroundStyle(isAvailable ? Color.accentColor : Color.secondary)
                        .clipShape(Circle())
                }
            }
        }
        .padding()
        .dashboardCard()
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Séances manquées")
                .font(.headline.bold())
            Text("Jours où tu étais disponible mais sans entraînement enregistré.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text("\(missedWorkoutsCount)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(missedWorkoutsCount > 0 ? Color.orange : Color.primary)
                Text("manquées")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .dashboardCard()
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Historique des semaines")
                .font(.headline.bold())
            ForEach(Array(weeklyHistory.enumerated()), id: \.offset) { _, week in
                HStack {
                    Text(weekLabel(week.weekStart))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(week.completed)/\(week.goal)")
                        .font(.subheadline.bold())
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding()
        .dashboardCard()
    }

    private func weekLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "d MMM"
        let cal = Calendar.current
        guard let end = cal.date(byAdding: .day, value: 6, to: date) else { return formatter.string(from: date) }
        return "\(formatter.string(from: date)) – \(formatter.string(from: end))"
    }

    private func weekdayToIndex(_ date: Date) -> Int {
        let cal = Calendar.current
        let w = cal.component(.weekday, from: date)
        return w == 1 ? 6 : w - 2
    }

    private func computeStreak() -> Int {
        let cal = Calendar.current
        let completedDates = Set(completedSessions.map { cal.startOfDay(for: $0.date) })
        let today = cal.startOfDay(for: Date())
        let availableSet = Set(availableDays)

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
            guard let prev = cal.date(byAdding: .day, value: -1, to: date) else { break }
            date = prev
        }
        return streak
    }

    private func computeMissedWorkouts() -> Int {
        let cal = Calendar.current
        let completedDates = Set(completedSessions.map { cal.startOfDay(for: $0.date) })
        let availableSet = Set(availableDays)
        var missed = 0
        var date = cal.startOfDay(for: Date())
        let startLimit = cal.date(byAdding: .day, value: -90, to: date) ?? date
        while date >= startLimit {
            let dayIndex = weekdayToIndex(date)
            if availableSet.contains(dayIndex) && !completedDates.contains(date) {
                missed += 1
            }
            guard let prev = cal.date(byAdding: .day, value: -1, to: date) else { break }
            date = prev
        }
        return missed
    }

    private func computeWeeklyHistory() -> [(weekStart: Date, completed: Int, goal: Int)] {
        let cal = Calendar.current
        let completedDates = Set(completedSessions.map { cal.startOfDay(for: $0.date) })
        let availableSet = Set(availableDays)
        let today = cal.startOfDay(for: Date())
        guard let currentWeekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) else { return [] }

        var result: [(Date, Int, Int)] = []
        for weekOffset in 0..<8 {
            guard let weekStart = cal.date(byAdding: .weekOfYear, value: -weekOffset, to: currentWeekStart) else { continue }
            var completed = 0
            for dayOffset in 0..<7 {
                guard let d = cal.date(byAdding: .day, value: dayOffset, to: weekStart) else { continue }
                if availableSet.contains(weekdayToIndex(d)) {
                    if completedDates.contains(d) { completed += 1 }
                }
            }
            let goal = (0..<7).filter { availableSet.contains($0) }.count
            result.append((weekStart, completed, max(1, goal)))
        }
        return result
    }
}
