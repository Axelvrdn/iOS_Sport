//
//  WorkoutView.swift
//  Muscu
//
//  Dashboard Workout au design moderne (cartes, jauge circulaire, streak, barre flottante).
//

import SwiftUI
import SwiftData
import EventKit

// MARK: - Dashboard Card (Liquid Glass : verre dépoli, flottant)

struct DashboardCardStyle: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding()
            .liquidGlassCard(cornerRadius: cornerRadius)
    }
}

extension View {
    func dashboardCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(DashboardCardStyle(cornerRadius: cornerRadius))
    }
}

// MARK: - Workout View (Dashboard principal)

struct WorkoutView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \WorkoutProgram.name) private var legacyWorkoutPrograms: [WorkoutProgram]
    /// Programmes (nouveau modèle) — source de vérité pour "Mes programmes" et "Programme actif".
    @Query(sort: \TrainingProgram.name) private var programs: [TrainingProgram]
    @Query(sort: \DailyLog.date, order: .reverse) private var logs: [DailyLog]
    @Query(sort: \WorkoutHistorySession.date, order: .reverse) private var sessions: [WorkoutHistorySession]

    @StateObject private var healthKit = HealthKitManager.shared
    @StateObject private var workoutManager = WorkoutManager.shared
    @State private var selectedProgram: WorkoutProgram?
    /// Programme actif : auto-sélectionné au premier apparu si la liste n'est pas vide.
    @State private var activeProgram: TrainingProgram?

    @State private var showChat: Bool = false
    @State private var showDebugDatabase: Bool = false
    @State private var showActiveSessionSheet: Bool = false
    @State private var showScheduleSheet: Bool = false
    @State private var scheduleDate: Date = Date()
    @State private var launchRunner: Bool = false
    @State private var showingCreationSheet: Bool = false
    @State private var programToEdit: TrainingProgram?
    @State private var pendingActivateProgram: TrainingProgram?

    private var userProfile: UserProfile? { profiles.first }

    private var evaluationScore: Int {
        let stepsScore = min(Double(healthKit.todaySteps) / 10_000.0, 1.0) * 30.0
        let sleepScore = min(healthKit.lastNightSleepHours / 8.0, 1.0) * 25.0
        let log = logs.first
        let soreness = 10 - Double(log?.sorenessLevel ?? 5)
        let mood = Double(log?.mood ?? 5)
        let recoveryScore = max(min((soreness + mood) / 20.0, 1.0), 0) * 20.0
        let recentSessions = sessions.prefix(7)
        let adherenceScore: Double
        if recentSessions.isEmpty {
            adherenceScore = 0.5 * 25.0
        } else {
            let avgCompletion = Double(recentSessions.map { $0.completionPercentage }.reduce(0, +)) / Double(recentSessions.count)
            let avgRest = Double(recentSessions.map { $0.averageRestTimeSeconds }.reduce(0, +)) / Double(recentSessions.count)
            let restScore = (avgRest >= 60 && avgRest <= 90) ? 1.0 : max(0.5, 1.0 - abs(avgRest - 75) / 75.0)
            adherenceScore = (avgCompletion / 100.0 * 0.7 + restScore * 0.3) * 25.0
        }
        return Int(stepsScore + sleepScore + recoveryScore + adherenceScore)
    }

    /// Programmes affichés dans la section "Mes programmes".
    private var displayedPrograms: [TrainingProgram] {
        programs
    }

    /// Programme actif affiché : source de vérité = UserProfile (persistance), puis state local, puis premier de la liste.
    private var displayedActiveProgram: TrainingProgram? {
        userProfile?.activeTrainingProgram ?? activeProgram ?? programs.first
    }

    /// Active un programme et persiste dans SwiftData (UserProfile.activeTrainingProgram).
    private func activateProgram(_ program: TrainingProgram) {
        guard let profile = userProfile else {
            activeProgram = program
            return
        }
        profile.activeTrainingProgram = program
        activeProgram = program
        do {
            try context.save()
        } catch {
            print("[WorkoutView] Erreur save activateProgram: \(error)")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    evaluationCard
                    NavigationLink {
                        StreakDetailView()
                    } label: {
                        StreakCardView(
                            currentStreak: workoutManager.currentStreak,
                            weeklyCurrent: workoutManager.weeklyWorkoutDays.current,
                            weeklyGoal: workoutManager.weeklyWorkoutDays.goal
                        )
                    }
                    .buttonStyle(.plain)
                    recommendedProgramsSection
                    activeProgramSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 100)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.large)
            .navigationTitle("Workout")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            showDebugDatabase = true
                        } label: {
                            Image(systemName: "ladybug.fill")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Debug base de données")
                        Button {
                            showChat = true
                        } label: {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.body)
                                .foregroundStyle(.primary)
                        }
                        .accessibilityLabel("Parler au coach IA")
                    }
                }
            }
            .navigationDestination(isPresented: $launchRunner) {
                SessionRunnerView(
                    program: workoutManager.suggestedProgram,
                    exercises: workoutManager.suggestedExercises,
                    phaseIndex: workoutManager.suggestedPhaseIndex,
                    dayIndex: workoutManager.suggestedDayIndex
                )
            }
            .navigationDestination(item: $programToEdit) { program in
                ProgramEditorView(program: program)
                    .onDisappear { programToEdit = nil }
            }
            .sheet(isPresented: $showDebugDatabase) {
                DebugDatabaseView()
            }
            .sheet(isPresented: $showChat) {
                ChatView(strictnessLevel: userProfile?.strictnessLevel ?? 0.5)
            }
            .sheet(isPresented: $showingCreationSheet) {
                NewProgramSheet { name, category in
                    let newProgram = DataController.createNewProgram(context: context, name: name, category: category)
                    programToEdit = newProgram
                }
            }
            .sheet(isPresented: $showActiveSessionSheet) {
                activeSessionOptionsSheet
            }
            .task {
                await healthKit.requestAuthorization()
                await healthKit.fetchTodaySteps()
                await healthKit.fetchLastNightSleep()
                workoutManager.refreshSuggestion(context: context)
            }
            .onAppear {
                // Source de vérité : toujours réhydrater depuis le profil (persistance après changement d’onglet)
                if let profileProgram = userProfile?.activeTrainingProgram {
                    activeProgram = profileProgram
                } else if activeProgram == nil, let firstProgram = programs.first {
                    activeProgram = firstProgram
                }
            }
            .onChange(of: userProfile?.activeTrainingProgram?.persistentModelID) { _, _ in
                activeProgram = userProfile?.activeTrainingProgram
            }
            .onChange(of: programs.count) { _, newCount in
                if let profileProgram = userProfile?.activeTrainingProgram {
                    activeProgram = profileProgram
                } else if activeProgram == nil, newCount > 0, let firstProgram = programs.first {
                    activeProgram = firstProgram
                }
            }
        }
    }

    // MARK: - Evaluation Card (jauge circulaire)

    private var evaluationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Évaluation du jour")
                .font(.headline.bold())
                .foregroundStyle(.primary)

            HStack(spacing: 24) {
                ZStack {
                    Circle()
                        .stroke(Color(.systemGray5), lineWidth: 10)
                        .frame(width: 100, height: 100)

                    Circle()
                        .trim(from: 0, to: CGFloat(evaluationScore) / 100.0)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    evaluationScore >= 70 ? Color.green : (evaluationScore >= 40 ? Color.orange : Color.red),
                                    evaluationScore >= 70 ? Color.green.opacity(0.7) : (evaluationScore >= 40 ? Color.orange.opacity(0.7) : Color.red.opacity(0.7))
                                ]),
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 0) {
                        Text("\(evaluationScore)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(evaluationScore >= 70 ? .green : (evaluationScore >= 40 ? .orange : .red))
                        Text("/ 100")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.walk")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Pas aujourd'hui : \(healthKit.todaySteps)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "bed.double.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Sommeil : \(healthKit.lastNightSleepHours, specifier: "%.1f") h")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .dashboardCard()
    }

    // MARK: - Mes programmes (TrainingProgram)

    private var recommendedProgramsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mes programmes")
                .font(.headline.bold())

            HStack(spacing: 12) {
                Button {
                    showingCreationSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Text("Ajouter un programme")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 10)
                    .padding(.leading, 12)
                    .padding(.trailing, 16)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                }
                .buttonStyle(.plain)

                if !displayedPrograms.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(displayedPrograms) { program in
                                let isActive = program.persistentModelID == displayedActiveProgram?.persistentModelID
                                programCard(program: program, isActive: isActive)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Carte programme : simple tap = activer, double tap = ouvrir l’éditeur.
    private func programCard(program: TrainingProgram, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(program.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            }
            Text(program.programDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .frame(width: 140, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.blue : Color.clear, lineWidth: 2)
        )
        .onTapGesture(count: 2) {
            pendingActivateProgram = nil
            programToEdit = program
        }
        .onTapGesture(count: 1) {
            pendingActivateProgram = program
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                if pendingActivateProgram?.persistentModelID == program.persistentModelID {
                    activateProgram(program)
                    pendingActivateProgram = nil
                }
            }
        }
    }

    // MARK: - Programme actif / Empty state

    private var activeProgramSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Programme actif")
                .font(.headline.bold())

            if let program = workoutManager.suggestedProgram, !workoutManager.suggestedExercises.isEmpty {
                let dayIndex = workoutManager.suggestedDayIndex
                let first = workoutManager.suggestedExercises.first
                VStack(alignment: .leading, spacing: 10) {
                    Text(program.name)
                        .font(.title3.bold())
                    Text(first?.dayName ?? "Jour \(dayIndex)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Divider()
                    Text("Prochaine séance suggérée")
                        .font(.subheadline.bold())
                    Text("Jour \(dayIndex) • \(first?.dayFocus ?? "")")
                        .font(.footnote)
                    Text("\(workoutManager.suggestedExercises.count) exercices")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button("Skip") { workoutManager.markSkipped(context: context) }
                            .buttonStyle(.bordered)
                        Button("Options") { showActiveSessionSheet = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 4)
                }
                .padding()
                .dashboardCard()
                .sheet(isPresented: $showActiveSessionSheet) {
                    activeSessionOptionsSheet
                }
            } else if let program = displayedActiveProgram {
                NavigationLink {
                    PlanningView()
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(program.name)
                                .font(.subheadline.bold())
                            Text(program.programDescription)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                    .dashboardCard()
                }
                .buttonStyle(.plain)
            } else {
                activeProgramEmptyCard
            }
        }
    }

    private var activeProgramEmptyCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "figure.run")
                .font(.system(size: 44))
                .foregroundStyle(Color(.systemGray3))

            VStack(alignment: .leading, spacing: 4) {
                Text("Aucune séance suggérée")
                    .font(.subheadline.bold())
                Text("Termine ta première séance pour démarrer la rotation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .dashboardCard()
    }

    private var activeSessionOptionsSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Button("Planifier") {
                    scheduleDate = Date()
                    showScheduleSheet = true
                }
                .buttonStyle(.borderedProminent)

                Button("Lancer la séance") {
                    showActiveSessionSheet = false
                    launchRunner = true
                }
                .buttonStyle(.borderedProminent)

                Button("Fermer") { showActiveSessionSheet = false }
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Séance")
            .sheet(isPresented: $showScheduleSheet) {
                NavigationStack {
                    VStack {
                        DatePicker("Date & heure", selection: $scheduleDate)
                            .datePickerStyle(.graphical)
                            .padding()
                        Button("Enregistrer dans le calendrier") {
                            Task {
                                await workoutManager.scheduleInCalendar(at: scheduleDate)
                                showScheduleSheet = false
                                showActiveSessionSheet = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding()
                    }
                    .navigationTitle("Planifier")
                }
            }
        }
    }
}

// MARK: - Streak Card (Flame)

struct StreakCardView: View {
    let currentStreak: Int
    let weeklyCurrent: Int
    let weeklyGoal: Int

    private var progress: CGFloat {
        guard weeklyGoal > 0 else { return 0 }
        return min(CGFloat(weeklyCurrent) / CGFloat(weeklyGoal), 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(currentStreak) Jours")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("Continue ta série !")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [.orange, .red],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, geo.size.width * progress), height: 6)
                    }
                }
                .frame(height: 6)
                Text("\(weeklyCurrent)/\(weeklyGoal)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .dashboardCard()
    }
}
