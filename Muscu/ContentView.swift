//
//  ContentView.swift
//  Muscu
//
//  Root structure : barre d’onglets flottante + contenu.
//

import SwiftUI
import SwiftData
import EventKit

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @State private var selectedTab: Int = 0
    @AppStorage("useDarkMode") private var useDarkMode: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case 0: WorkoutView()
                case 1: PlanningView()
                case 2: SettingsView()
                default: WorkoutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            CustomFloatingTabBar(selectedTab: $selectedTab)
        }
        .preferredColorScheme(useDarkMode ? .dark : .light)
        .ignoresSafeArea(.keyboard)
    }
}

// MARK: - Barre d’onglets flottante (Liquid Glass)

struct CustomFloatingTabBar: View {
    @Binding var selectedTab: Int

    var body: some View {
        HStack(spacing: 0) {
            tabItem(index: 0, title: "Workout", icon: "figure.strengthtraining.traditional")
            tabItem(index: 1, title: "Planning", icon: "calendar")
            tabItem(index: 2, title: "Paramètres", icon: "gearshape.fill")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .liquidGlassTabBar()
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private func tabItem(index: Int, title: String, icon: String) -> some View {
        let isSelected = selectedTab == index
        return Button {
            selectedTab = index
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: isSelected ? .semibold : .medium))
                    .symbolVariant(isSelected ? .fill : .none)
                    .foregroundStyle(isSelected ? Color.accentColor : Color(.secondaryLabel))
                    .shadow(color: isSelected ? Color.accentColor.opacity(0.4) : .clear, radius: 6)
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(isSelected ? Color.accentColor : Color(.secondaryLabel))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Planning View (Daily Agenda)

struct PlanningView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \TrainingProgram.name) private var programs: [TrainingProgram]
    
    @State private var selectedDate: Date = Date()
    @State private var showDatePicker = false
    @State private var dragOffset: CGFloat = 0
    
    /// Programme affiché : priorité au programme actif du profil (cohérent avec WorkoutView).
    private var currentProgram: TrainingProgram? {
        profiles.first?.activeTrainingProgram ?? programs.first
    }
    
    // Calculer le jour d'entraînement correspondant à la date sélectionnée
    private var currentTrainingDay: TrainingDay? {
        guard let program = currentProgram else { return nil }
        
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        let daysSinceStart = calendar.dateComponents([.day], from: startOfWeek, to: selectedDate).day ?? 0
        let weekIndex = daysSinceStart / 7
        let dayInWeek = daysSinceStart % 7
        
        guard weekIndex < program.weeks.count else { return nil }
        let week = program.weeks.sorted { $0.weekNumber < $1.weekNumber }[weekIndex]
        
        guard dayInWeek < week.days.count else { return nil }
        return week.days.sorted { $0.dayIndex < $1.dayIndex }[dayInWeek]
    }
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header: Date Navigation Strip
                dateNavigationHeader
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                
                // Main Content avec gesture de swipe
                ScrollView {
                    VStack(spacing: 20) {
                        if let day = currentTrainingDay {
                            if day.isRestDay {
                                restDayCard
                            } else if let recipe = day.sessionRecipe {
                                workoutSessionCard(day: day, recipe: recipe)
                            } else {
                                emptyStateCard
                            }
                        } else {
                            emptyStateCard
                        }
                    }
                    .padding()
                    .offset(x: dragOffset)
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation.width * 0.3
                        }
                        .onEnded { value in
                            let threshold: CGFloat = 80
                            if value.translation.width > threshold {
                                // Swipe right = jour précédent
                                withAnimation(.spring(response: 0.3)) {
                                    changeDay(by: -1)
                                    dragOffset = 0
                                }
                            } else if value.translation.width < -threshold {
                                // Swipe left = jour suivant
                                withAnimation(.spring(response: 0.3)) {
                                    changeDay(by: 1)
                                    dragOffset = 0
                                }
                            } else {
                                withAnimation(.spring(response: 0.3)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
            }
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selectedDate: $selectedDate)
        }
    }
    
    // MARK: - Date Navigation Header
    
    private var dateNavigationHeader: some View {
        HStack(spacing: 20) {
            // Bouton précédent
            Button {
                withAnimation(.spring(response: 0.3)) {
                    changeDay(by: -1)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color(.secondarySystemFill))
                    .clipShape(Circle())
            }
            
            // Date centrale (tappable)
            Button {
                showDatePicker = true
            } label: {
                Text(dateDisplayText)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // Bouton suivant
            Button {
                withAnimation(.spring(response: 0.3)) {
                    changeDay(by: 1)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color(.secondarySystemFill))
                    .clipShape(Circle())
            }
        }
    }
    
    private var dateDisplayText: String {
        let calendar = Calendar.current
        let today = Date()
        
        if calendar.isDateInToday(selectedDate) {
            return "Aujourd'hui"
        } else if calendar.isDateInTomorrow(selectedDate) {
            return "Demain"
        } else if calendar.isDate(selectedDate, equalTo: today.addingTimeInterval(-86400), toGranularity: .day) {
            return "Hier"
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "fr_FR")
            formatter.dateFormat = "EEEE d MMM"
            return formatter.string(from: selectedDate).capitalized
        }
    }
    
    private func changeDay(by days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) {
            selectedDate = newDate
        }
    }
    
    // MARK: - Workout Session Card (Scenario A)
    
    private func workoutSessionCard(day: TrainingDay, recipe: SessionRecipe) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header avec gradient basé sur le bodyFocus
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.name)
                        .font(.title2.bold())
                    Text(bodyFocusLabel(recipe.bodyFocus))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                
                // Badge durée estimée
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                    Text("1h 30")
                        .font(.caption.bold())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(bodyFocusColor(recipe.bodyFocus).opacity(0.8))
                .clipShape(Capsule())
            }
            
            // Tag focus
            HStack(spacing: 8) {
                ForEach([sessionGoalLabel(recipe.goal)], id: \.self) { tag in
                    Text(tag)
                        .font(.caption.bold())
                        .foregroundStyle(bodyFocusColor(recipe.bodyFocus))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(bodyFocusColor(recipe.bodyFocus).opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            
            // Liste d'exercices (preview)
            if !recipe.exercises.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Exercices")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    
                    let exerciseNames = recipe.exercises.prefix(3).compactMap { $0.exercise?.name }
                    let preview = exerciseNames.joined(separator: ", ")
                    let suffix = recipe.exercises.count > 3 ? "..." : ""
                    
                    Text(preview + suffix)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
            }
            
            Divider()
            
            // Action button
            NavigationLink {
                SessionRunnerView(
                    program: nil,
                    exercises: day.exercises,
                    phaseIndex: 1,
                    dayIndex: day.dayIndex + 1
                )
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Lancer la séance")
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [bodyFocusColor(recipe.bodyFocus), bodyFocusColor(recipe.bodyFocus).opacity(0.7)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(20)
        .liquidGlassCard(cornerRadius: 20)
    }
    
    // MARK: - Rest Day Card (Scenario B)
    
    private var restDayCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "bed.double.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Jour de repos")
                        .font(.title2.bold())
                    Text("Récupération active")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                motivationalQuote
                
                Text("Suggestions")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                
                restSuggestion(icon: "figure.walk", text: "Marche légère (20-30 min)")
                restSuggestion(icon: "figure.yoga", text: "Étirements ou yoga")
                restSuggestion(icon: "moon.zzz.fill", text: "Objectif: 8h de sommeil")
            }
        }
        .padding(20)
        .liquidGlassCard(cornerRadius: 20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.green.opacity(0.3), lineWidth: 2)
        )
    }
    
    private var motivationalQuote: some View {
        Text("« Le repos fait partie de l'entraînement. C'est pendant la récupération que tes muscles se construisent. »")
            .font(.body.italic())
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
    }
    
    private func restSuggestion(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 32, height: 32)
                .background(Color.green.opacity(0.1))
                .clipShape(Circle())
            
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
            
            Spacer()
        }
    }
    
    // MARK: - Empty State Card (Scenario C)
    
    private var emptyStateCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 8) {
                Text("Aucun entraînement prévu")
                    .font(.title3.bold())
                Text("Planifie une séance ou marque ce jour comme repos")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 12) {
                Button {
                    // Action: Ajouter une séance
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Ajouter une séance")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                
                Button {
                    // Action: Marquer comme repos
                } label: {
                    HStack {
                        Image(systemName: "bed.double.fill")
                        Text("Planifier du repos")
                            .font(.headline)
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.secondarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .padding(30)
        .liquidGlassCard(cornerRadius: 20)
    }
    
    // MARK: - Helper Functions
    
    private func bodyFocusLabel(_ focus: BodyFocus) -> String {
        switch focus {
        case .upper: return "Haut du corps"
        case .lower: return "Bas du corps"
        case .push: return "Poussée"
        case .pull: return "Traction"
        case .fullBody: return "Corps entier"
        }
    }
    
    private func sessionGoalLabel(_ goal: SessionGoal) -> String {
        switch goal {
        case .volume: return "Volume"
        case .strength: return "Force"
        case .technique: return "Technique"
        case .endurance: return "Endurance"
        case .rehab: return "Réhabilitation"
        }
    }
    
    private func bodyFocusColor(_ focus: BodyFocus) -> Color {
        switch focus {
        case .upper: return .blue
        case .lower: return .green
        case .push: return .orange
        case .pull: return .purple
        case .fullBody: return .indigo
        }
    }
}

// MARK: - Date Picker Sheet

private struct DatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDate: Date
    
    var body: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "Sélectionner une date",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .padding()
                
                Spacer()
            }
            .navigationTitle("Choisir une date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            UserProfile.self,
            WorkoutProgram.self,
            Exercise.self,
            DailyLog.self,
            WorkoutHistorySession.self,
            WorkoutLog.self,
            TrainingProgram.self,
            TrainingWeek.self,
            TrainingDay.self,
            WorkoutSession.self
        ])
}
