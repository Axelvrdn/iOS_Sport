//
//  WorkoutView.swift
//  Muscu
//
//  Rôle : Dashboard Workout (évaluation du jour, streak, Mes programmes, Programme actif) ; design Elite Athlete.
//  Utilisé par : ContentView (onglet 0).
//

import SwiftUI
import SwiftData
import EventKit

// MARK: - Elite Design System (adaptatif Light / Dark)

private enum EliteDesign {
    static let accentVolt = Color(hex: "D0FD3E")
    /// Même Vert Volt électrique qu'en dark (Premium Apple).
    static let accentVoltLight = Color(hex: "D0FD3E")
    static let cornerRadiusLarge: CGFloat = 24
    static let cornerRadiusSmall: CGFloat = 16
    static let cardBorderWidth: CGFloat = 0.5
    static let horizontalPadding: CGFloat = 20

    /// Fond de page : système (Light) / Deep Charcoal (Dark).
    static func background(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "0F1115") : Color(.systemGroupedBackground)
    }

    /// Fond des cartes : gris très léger (Light) / Charcoal (Dark).
    static func cardBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "1C1F26") : Color(.secondarySystemGroupedBackground)
    }

    /// Bordure des cartes : gris discret (Light) / blanc 10% (Dark).
    static func cardBorder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.2)
    }

    /// Couleur accent (boutons, indicateurs) : Volt clair (Dark) / Herbe (Light).
    static func accent(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? accentVolt : accentVoltLight
    }

    /// Texte sur bouton accent : noir en light (lisibilité max), charcoal en dark.
    static func textOnAccent(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "0F1115") : .black
    }

    static var sectionTitleFont: Font {
        .system(size: 17, weight: .bold, design: .rounded)
    }
    static var sectionTitleFontCondensed: Font {
        .system(size: 15, weight: .black, design: .rounded)
    }
    static var numberFont: Font {
        .system(.body, design: .monospaced)
            .weight(.semibold)
    }
    static var impactStreakFont: Font {
        .system(size: 28, weight: .heavy, design: .rounded)
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Carte Elite (fond et bordure adaptatifs Light/Dark)

private struct EliteCardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = EliteDesign.cornerRadiusLarge
    var useMaterial: Bool = false

    func body(content: Content) -> some View {
        content
            .padding()
            .background {
                Group {
                    if useMaterial {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.ultraThinMaterial)
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(EliteDesign.cardBackground(for: colorScheme))
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(EliteDesign.cardBorder(for: colorScheme), lineWidth: EliteDesign.cardBorderWidth)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.06), radius: 8, x: 0, y: 2)
    }
}

private extension View {
    func eliteCard(cornerRadius: CGFloat = EliteDesign.cornerRadiusLarge, material: Bool = false) -> some View {
        modifier(EliteCardStyle(cornerRadius: cornerRadius, useMaterial: material))
    }
}

// MARK: - Bouton scale au tap (0.98)

private struct EliteScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Navigation programme (ID stable)

private struct ProgramNavItem: Identifiable, Equatable, Hashable {
    let id: PersistentIdentifier
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Workout View (Dashboard Elite)

struct WorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentColor) private var accentColor
    @Environment(\.textOnAccentColor) private var textOnAccentColor
    @Query private var profiles: [UserProfile]
    @Query(sort: \TrainingProgram.name) private var programs: [TrainingProgram]
    @Query(sort: \DailyLog.date, order: .reverse) private var logs: [DailyLog]
    @Query(sort: \WorkoutHistorySession.date, order: .reverse) private var sessions: [WorkoutHistorySession]

    @State private var workoutManager = WorkoutManager.shared
    @State private var activeProgram: TrainingProgram?
    @State private var showChat: Bool = false
    @State private var showDebugDatabase: Bool = false
    @State private var showActiveSessionSheet: Bool = false
    @State private var showScheduleSheet: Bool = false
    @State private var scheduleDate: Date = Date()
    @State private var launchRunner: Bool = false
    @State private var showingCreationSheet: Bool = false
    @State private var programToEdit: ProgramNavItem?
    @State private var pendingActivateProgram: TrainingProgram?

    private var userProfile: UserProfile? { profiles.first }

    private var lastSessionSummary: String? {
        guard let session = sessions.first else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "\(session.programName.isEmpty ? "Séance" : session.programName) • \(formatter.string(from: session.date))"
    }

    private var displayedPrograms: [TrainingProgram] { programs }

    private var displayedActiveProgram: TrainingProgram? {
        userProfile?.activeTrainingProgram ?? activeProgram ?? programs.first
    }

    /// Log du jour pour l’évaluation (Pas, Sommeil).
    private var todayLog: DailyLog? {
        let calendar = Calendar.current
        return logs.first { calendar.isDateInToday($0.date) }
    }

    /// True si une séance du jour a été complétée (flamme en couleur).
    private var isTodayWorkoutCompleted: Bool {
        let calendar = Calendar.current
        return sessions.contains { calendar.isDateInToday($0.date) && $0.isCompleted }
    }

    private func activateProgram(_ program: TrainingProgram) {
        guard let profile = userProfile else {
            activeProgram = program
            return
        }
        profile.activeTrainingProgram = program
        activeProgram = program
        try? context.save()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    dayEvaluationHeader
                    NavigationLink {
                        StreakDetailView()
                    } label: {
                        EliteStreakCardView(
                            currentStreak: workoutManager.currentStreak,
                            weeklyCurrent: workoutManager.weeklyWorkoutDays.current,
                            weeklyGoal: workoutManager.weeklyWorkoutDays.goal,
                            isTodayWorkoutCompleted: isTodayWorkoutCompleted
                        )
                    }
                    .buttonStyle(EliteScaleButtonStyle())
                    recommendedProgramsSection
                    activeProgramSection
                }
                .padding(.horizontal, EliteDesign.horizontalPadding)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
            .background(EliteDesign.background(for: colorScheme))
            .scrollIndicators(.hidden)
            .navigationBarTitleDisplayMode(.large)
            .navigationTitle("Workout")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button { showDebugDatabase = true } label: {
                            Image(systemName: "ladybug.fill")
                                .font(.body)
                                .foregroundStyle(Color.secondary)
                        }
                        .accessibilityLabel("Debug base de données")
                        Button { showChat = true } label: {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.body)
                                .foregroundStyle(accentColor)
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
            .navigationDestination(item: $programToEdit) { item in
                if let program = context.model(for: item.id) as? TrainingProgram {
                    ProgramEditorView(program: program)
                        .id(item.id)
                        .onDisappear { programToEdit = nil }
                } else {
                    ContentUnavailableView("Programme introuvable", systemImage: "doc.badge.gearshape")
                        .onDisappear { programToEdit = nil }
                }
            }
            .navigationDestination(for: PersistentIdentifier.self) { dayID in
                DayEditorView(dayID: dayID, onDismiss: nil)
                    .id(dayID)
            }
            .sheet(isPresented: $showDebugDatabase) { DebugDatabaseView() }
            .sheet(isPresented: $showChat) { AICoachView(strictnessLevel: userProfile?.strictnessLevel ?? 0.5, activeProgram: activeProgram) }
            .sheet(isPresented: $showingCreationSheet) {
                NewProgramSheet { name, category in
                    let newProgram = DataController.createNewProgram(context: context, name: name, category: category)
                    programToEdit = ProgramNavItem(id: newProgram.persistentModelID)
                }
            }
            .sheet(isPresented: $showActiveSessionSheet) { activeSessionOptionsSheet }
            .task { workoutManager.refreshSuggestion(context: context) }
            .onAppear {
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

    // MARK: - Header Évaluation du jour (jauge semi-cercle, Pas, Sommeil)

    private var dayEvaluationHeader: some View {
        let steps = todayLog?.steps ?? 0
        let sleepQuality = todayLog?.sleepQuality ?? 5
        let dayScore = min(10, (min(steps / 1000, 10) + sleepQuality) / 2)
        let progress = CGFloat(dayScore) / 10.0

        return HStack(spacing: 20) {
            ZStack {
                SemiCircleGauge(progress: progress)
            }
            .frame(width: 88, height: 52)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 14, weight: .ultraLight))
                            .foregroundStyle(Color.secondary)
                        Text("\(steps)")
                            .font(EliteDesign.numberFont)
                            .foregroundStyle(Color.primary)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "moon.zzz")
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(Color.secondary)
                        Text("\(sleepQuality)/10")
                            .font(EliteDesign.numberFont)
                            .foregroundStyle(Color.primary)
                    }
                }
                if let summary = lastSessionSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                } else {
                    Text("Lance une séance pour commencer.")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .eliteCard(cornerRadius: EliteDesign.cornerRadiusLarge, material: true)
    }

    // MARK: - Mes programmes

    private var recommendedProgramsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mes programmes")
                .font(EliteDesign.sectionTitleFont)
                .foregroundStyle(Color.primary)

            HStack(spacing: 12) {
                Button { showingCreationSheet = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(textOnAccentColor)
                        Text("Ajouter")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(textOnAccentColor)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: EliteDesign.cornerRadiusSmall))
                }
                .buttonStyle(EliteScaleButtonStyle())

                if !displayedPrograms.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(displayedPrograms) { program in
                                let isActive = program.persistentModelID == displayedActiveProgram?.persistentModelID
                                eliteProgramCard(program: program, isActive: isActive)
                            }
                        }
                    }
                }
            }
        }
    }

    private func eliteProgramCard(program: TrainingProgram, isActive: Bool) -> some View {
        EliteProgramCardContent(
            program: program,
            isActive: isActive,
            categoryColor: categoryColor(for: program.sportCategories.first, colorScheme: colorScheme),
            onSingleTap: {
                pendingActivateProgram = program
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    if pendingActivateProgram?.persistentModelID == program.persistentModelID {
                        activateProgram(program)
                        pendingActivateProgram = nil
                    }
                }
            },
            onDoubleTap: {
                pendingActivateProgram = nil
                programToEdit = ProgramNavItem(id: program.persistentModelID)
            }
        )
    }

    private func categoryColor(for category: SportCategory?, colorScheme: ColorScheme) -> Color? {
        guard let category = category else { return nil }
        switch category {
        case .bodybuilding: return Color.orange
        case .volley: return Color.blue
        case .basket: return Color.red
        case .running: return Color.green
        case .boxing: return Color.purple
        case .general: return accentColor
        }
    }

    // MARK: - Programme actif (Carte Hero)

    private var activeProgramSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Programme actif")
                .font(EliteDesign.sectionTitleFont)
                .foregroundStyle(Color.primary)

            if let program = workoutManager.suggestedProgram, !workoutManager.suggestedExercises.isEmpty {
                heroSuggestedSessionCard(program: program)
            } else if let program = displayedActiveProgram {
                NavigationLink {
                    PlanningView()
                } label: {
                    heroActiveProgramCard(program: program)
                }
                .buttonStyle(EliteScaleButtonStyle())
            } else {
                heroEmptyCard
            }
        }
    }

    private func heroSuggestedSessionCard(program: WorkoutProgram) -> some View {
        let dayIndex = workoutManager.suggestedDayIndex
        let first = workoutManager.suggestedExercises.first
        let cardBg = EliteDesign.cardBackground(for: colorScheme)
        return ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [cardBg, cardBg.opacity(0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 120, weight: .ultraLight))
                .foregroundStyle(Color.primary.opacity(0.05))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 20)

            VStack(alignment: .leading, spacing: 12) {
                Text(program.name)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(Color.primary)
                Text(first?.dayName ?? "Jour \(dayIndex)")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                Text("\(workoutManager.suggestedExercises.count) exercices • \(first?.dayFocus ?? "")")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                HStack(spacing: 12) {
                    Button("Skip") { workoutManager.markSkipped(context: context) }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.secondary)
                    Button("Options") { showActiveSessionSheet = true }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(textOnAccentColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.top, 4)

                Button {
                    showActiveSessionSheet = false
                    launchRunner = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("START SESSION")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(textOnAccentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: EliteDesign.cornerRadiusSmall))
                }
                .buttonStyle(EliteScaleButtonStyle())
                .padding(.top, 4)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: EliteDesign.cornerRadiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: EliteDesign.cornerRadiusLarge)
                .strokeBorder(EliteDesign.cardBorder(for: colorScheme), lineWidth: EliteDesign.cardBorderWidth)
        )
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        .glow(color: colorScheme == .light ? accentColor : .clear, opacity: 0.3, radius: 20, y: 12)
        .sheet(isPresented: $showActiveSessionSheet) { activeSessionOptionsSheet }
    }

    private func heroActiveProgramCard(program: TrainingProgram) -> some View {
        let cardBg = EliteDesign.cardBackground(for: colorScheme)
        return ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [cardBg, cardBg.opacity(0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "doc.text.fill")
                .font(.system(size: 80, weight: .ultraLight))
                .foregroundStyle(Color.primary.opacity(0.05))
                .padding(24)
            VStack(alignment: .leading, spacing: 8) {
                Text(program.name)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(Color.primary)
                if !program.programDescription.isEmpty {
                    Text(program.programDescription)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                }
                HStack {
                    Text("Voir le planning")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(accentColor)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: EliteDesign.cornerRadiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: EliteDesign.cornerRadiusLarge)
                .strokeBorder(EliteDesign.cardBorder(for: colorScheme), lineWidth: EliteDesign.cardBorderWidth)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
    }

    private var heroEmptyCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "figure.run")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(Color.secondary.opacity(0.6))
            VStack(alignment: .leading, spacing: 4) {
                Text("Aucune séance suggérée")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary)
                Text("Termine ta première séance pour démarrer la rotation.")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(EliteDesign.cardBackground(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: EliteDesign.cornerRadiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: EliteDesign.cornerRadiusLarge)
                .strokeBorder(EliteDesign.cardBorder(for: colorScheme), lineWidth: EliteDesign.cardBorderWidth)
        )
    }

    private var activeSessionOptionsSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Button("Planifier") {
                    scheduleDate = Date()
                    showScheduleSheet = true
                }
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(textOnAccentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(accentColor)
                .clipShape(RoundedRectangle(cornerRadius: EliteDesign.cornerRadiusSmall))

                Button("Lancer la séance") {
                    showActiveSessionSheet = false
                    launchRunner = true
                }
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(colorScheme == .light ? .black : accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .overlay(
                    RoundedRectangle(cornerRadius: EliteDesign.cornerRadiusSmall)
                        .strokeBorder(accentColor, lineWidth: 1.5)
                )

                Button("Fermer") { showActiveSessionSheet = false }
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }
            .padding(EliteDesign.horizontalPadding)
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
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(textOnAccentColor)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: EliteDesign.cornerRadiusSmall))
                    }
                    .navigationTitle("Planifier")
                }
            }
        }
    }
}

// MARK: - Carte programme avec scale au tap

private struct EliteProgramCardContent: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentColor) private var accentColor
    let program: TrainingProgram
    let isActive: Bool
    let categoryColor: Color?
    let onSingleTap: () -> Void
    let onDoubleTap: () -> Void
    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 8) {
            if let color = categoryColor {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            Text(program.name)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 140, alignment: .leading)
        .background(EliteDesign.cardBackground(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: EliteDesign.cornerRadiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: EliteDesign.cornerRadiusSmall)
                .strokeBorder(isActive ? accentColor : EliteDesign.cardBorder(for: colorScheme), lineWidth: isActive ? 1.5 : EliteDesign.cardBorderWidth)
        )
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isPressed)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onDoubleTap)
        .onTapGesture(count: 1, perform: onSingleTap)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Jauge semi-circulaire (Glow / progression)

private struct SemiCircleGauge: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentColor) private var accentColor
    let progress: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            Circle()
                .trim(from: 0.25, to: 0.75)
                .stroke(
                    Color.primary.opacity(0.12),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
            Circle()
                .trim(from: 0.25, to: 0.25 + 0.5 * progress)
                .stroke(
                    LinearGradient(
                        colors: [accentColor.opacity(0.8), accentColor],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .glow(color: accentColor, opacity: 0.5, radius: 4)
        }
    }
}

// MARK: - Streak Elite (compact, flamme couleur ou grisée selon entraînement du jour)

struct EliteStreakCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentColor) private var accentColor
    let currentStreak: Int
    let weeklyCurrent: Int
    let weeklyGoal: Int
    /// Si false, la flamme est grisée et en opacité réduite.
    var isTodayWorkoutCompleted: Bool = false

    private var progress: CGFloat {
        guard weeklyGoal > 0 else { return 0 }
        return min(CGFloat(weeklyCurrent) / CGFloat(weeklyGoal), 1.0)
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "flame.fill")
                .font(.system(size: 36))
                .foregroundStyle(
                    isTodayWorkoutCompleted
                        ? LinearGradient(
                            colors: [.yellow, accentColor],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                        : LinearGradient(colors: [Color.gray, Color.gray], startPoint: .top, endPoint: .bottom)
                )
                .grayscale(isTodayWorkoutCompleted ? 0 : 1.0)
                .opacity(isTodayWorkoutCompleted ? 1.0 : 0.4)
            VStack(alignment: .leading, spacing: 4) {
                Text(currentStreak == 0 ? "0 jour" : "\(currentStreak) JOURS")
                    .font(currentStreak == 0 ? .subheadline.weight(.medium) : EliteDesign.impactStreakFont)
                    .foregroundStyle(currentStreak == 0 ? Color.secondary : Color.primary)
                Text(currentStreak == 0 ? "Lance une séance pour démarrer" : "Continue ta série")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 0)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.1))
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [.yellow.opacity(0.9), accentColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geo.size.width * progress), height: 5)
                }
            }
            .frame(width: 56, height: 5)
            Text("\(weeklyCurrent)/\(weeklyGoal)")
                .font(EliteDesign.numberFont)
                .font(.caption)
                .foregroundStyle(Color.secondary)
        }
        .padding(16)
        .eliteCard(cornerRadius: EliteDesign.cornerRadiusLarge)
        .glow(color: colorScheme == .light ? accentColor : .clear, opacity: 0.3, radius: 20, y: 12)
    }
}

#Preview("WorkoutView") {
    WorkoutView()
        .modelContainer(for: [UserProfile.self, TrainingProgram.self, DailyLog.self, WorkoutHistorySession.self], inMemory: true)
}
