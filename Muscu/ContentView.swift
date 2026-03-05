//
//  ContentView.swift
//  Muscu
//
//  Rôle : Structure racine à onglets (Workout, Planning, Paramètres) + CustomTabBar ; contient PlanningView et helpers.
//  Utilisé par : MuscuApp (RootView).
//

import SwiftUI
import SwiftData
import EventKit
import Observation
import Combine

// MARK: - Accent Color (personnalisable via Réglages)

private let DefaultAccentHex = "#D0FD3E"

// MARK: - TabBar visibilité (masquage automatique en sous-pages)

@Observable
final class TabBarVisibilityStore {
    var isSubPageActive: Bool = false
}

extension EnvironmentValues {
    private struct TabBarVisibilityStoreKey: EnvironmentKey {
        static let defaultValue: TabBarVisibilityStore? = nil
    }
    var tabBarVisibilityStore: TabBarVisibilityStore? {
        get { self[TabBarVisibilityStoreKey.self] }
        set { self[TabBarVisibilityStoreKey.self] = newValue }
    }
}

extension EnvironmentValues {
    private struct AccentColorKey: EnvironmentKey {
        static let defaultValue: Color = Color(hex: "D0FD3E")
    }
    private struct TextOnAccentColorKey: EnvironmentKey {
        static let defaultValue: Color = Color(hex: "0F1115")
    }
    var accentColor: Color {
        get { self[AccentColorKey.self] }
        set { self[AccentColorKey.self] = newValue }
    }
    var textOnAccentColor: Color {
        get { self[TextOnAccentColorKey.self] }
        set { self[TextOnAccentColorKey.self] = newValue }
    }
}

func accentColorFromHex(_ hex: String) -> Color {
    Color(hex: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
}

func textOnAccentColorFromHex(_ hex: String) -> Color {
    let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard h.count == 6 else { return Color(hex: "0F1115") }
    var int: UInt64 = 0
    Scanner(string: h).scanHexInt64(&int)
    let r = Double((int >> 16) & 0xFF) / 255
    let g = Double((int >> 8) & 0xFF) / 255
    let b = Double(int & 0xFF) / 255
    let luminance = 0.299 * r + 0.587 * g + 0.114 * b
    return luminance > 0.6 ? .black : Color(hex: "0F1115")
}

// MARK: - Glow dynamique (accent)

extension View {
    func glow(color: Color, opacity: Double = 0.5, radius: CGFloat = 8, y: CGFloat? = nil) -> some View {
        self.shadow(color: color.opacity(opacity), radius: radius, x: 0, y: y ?? radius / 2)
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @State private var tabBarVisibilityStore = TabBarVisibilityStore()
    @State private var selectedTab: Int = 0
    @State private var isSessionRunnerActive: Bool = false
    @AppStorage("useDarkMode") private var useDarkMode: Bool = false
    @AppStorage("accentColorHex") private var accentColorHex: String = DefaultAccentHex

    private var accentColor: Color { accentColorFromHex(accentColorHex) }
    private var textOnAccentColor: Color { textOnAccentColorFromHex(accentColorHex) }

    /// Afficher la TabBar uniquement à la racine (pas en sous-page) et pas pendant une session.
    private var shouldShowTabBar: Bool {
        !isSessionRunnerActive && !tabBarVisibilityStore.isSubPageActive
    }

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
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .animation(.easeInOut(duration: 0.28), value: selectedTab)

            if shouldShowTabBar {
                CustomTabBar(selectedTab: $selectedTab)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
            }
        }
        .environment(\.accentColor, accentColor)
        .environment(\.textOnAccentColor, textOnAccentColor)
        .environment(\.tabBarVisibilityStore, tabBarVisibilityStore)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: isSessionRunnerActive)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: shouldShowTabBar)
        .preferredColorScheme(useDarkMode ? .dark : .light)
        .ignoresSafeArea(.keyboard)
        .onReceive(NotificationCenter.default.publisher(for: .sessionRunnerDidAppear)) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                isSessionRunnerActive = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionRunnerDidDisappear)) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                isSessionRunnerActive = false
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab != 2 {
                tabBarVisibilityStore.isSubPageActive = false
            }
        }
    }
}

// MARK: - Custom Tab Bar (Elite Athlete DA, adaptatif Light/Dark)

private let EliteTabBarBackgroundDark = Color(hex: "1C1F26")

struct CustomTabBar: View {
    @Binding var selectedTab: Int
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentColor) private var accentColor

    private let tabs: [(id: Int, icon: String, label: String)] = [
        (0, "figure.strengthtraining.traditional", "Workout"),
        (1, "calendar", "Planning"),
        (2, "gearshape.fill", "Paramètres")
    ]

    private var tabBarBackground: Color {
        colorScheme == .dark
            ? EliteTabBarBackgroundDark.opacity(0.8)
            : Color(UIColor.secondarySystemGroupedBackground).opacity(0.95)
    }

    /// Icône active : accent ; en mode clair si accent trop claire, assombrir pour lisibilité.
    private var activeTint: Color {
        accentColor
    }

    private var tabBarBorder: Color {
        colorScheme == .dark ? Color.primary.opacity(0.1) : Color.gray.opacity(0.2)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.id) { tab in
                tabItem(id: tab.id, icon: tab.icon, label: tab.label)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .background {
            ZStack {
                tabBarBackground
                Rectangle()
                    .fill(colorScheme == .dark ? .ultraThinMaterial : .thinMaterial)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 30)
                .strokeBorder(tabBarBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.12), radius: colorScheme == .dark ? 12 : 20, x: 0, y: colorScheme == .dark ? 4 : 6)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private func tabItem(id: Int, icon: String, label: String) -> some View {
        let isSelected = (selectedTab == id)
        let inactiveColor: Color = colorScheme == .dark ? Color.secondary : Color.gray
        return Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                selectedTab = id
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 25, weight: isSelected ? .semibold : .regular))
                    .symbolVariant(isSelected ? .fill : .none)
                    .foregroundStyle(isSelected ? activeTint : inactiveColor)
                    .brightness(isSelected && colorScheme == .light ? -0.1 : 0)
                    .shadow(color: isSelected ? activeTint.opacity(0.4) : .clear, radius: 4)
                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(activeTint)
                        .frame(width: 28, height: 2.5)
                        .shadow(color: activeTint.opacity(0.5), radius: 3)
                }
                if isSelected {
                    Text(label)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(activeTint)
                        .brightness(colorScheme == .light ? -0.1 : 0)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - Contexte pour la sheet de planification (Identifiable pour .sheet(item:))

private struct SchedulingSessionContext: Identifiable {
    let id = UUID()
    let title: String
    let durationMinutes: Int
    let initialDate: Date?
    let excludedEventID: String?
}

// MARK: - Persistance heure planifiée + event ID (UserDefaults)

private func schedulingStorageKey(date: Date, title: String) -> String {
    let cal = Calendar.current
    let startOfDay = cal.startOfDay(for: date)
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = cal.timeZone
    let dayKey = formatter.string(from: startOfDay)
    return "muscu_sched_\(dayKey)_\(title)"
}

private func storedScheduledTime(date: Date, title: String) -> Date? {
    let key = schedulingStorageKey(date: date, title: title)
    let interval = UserDefaults.standard.double(forKey: key)
    guard interval > 0 else { return nil }
    let d = Date(timeIntervalSince1970: interval)
    return Calendar.current.isDate(d, inSameDayAs: date) ? d : nil
}

private func persistScheduledTime(date: Date, title: String, time: Date) {
    UserDefaults.standard.set(time.timeIntervalSince1970, forKey: schedulingStorageKey(date: date, title: title))
}

private func eventIDStorageKey(date: Date, title: String) -> String {
    "muscu_sched_id_" + schedulingStorageKey(date: date, title: title)
}

private func storedCalendarEventID(date: Date, title: String) -> String? {
    let key = eventIDStorageKey(date: date, title: title)
    let id = UserDefaults.standard.string(forKey: key)
    return id?.isEmpty == true ? nil : id
}

private func persistCalendarEventID(date: Date, title: String, eventID: String?) {
    let key = eventIDStorageKey(date: date, title: title)
    if let id = eventID {
        UserDefaults.standard.set(id, forKey: key)
    } else {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - Planning View (Daily Agenda — DA Deep Charcoal & Volt, adaptatif Light/Dark)

private let PlanningCardBg = Color(hex: "1C1F26")
private let PlanningBackgroundDark = Color(hex: "0F1115")
private let PlanningDayLabels = ["L", "M", "M", "J", "V", "S", "D"]

struct PlanningView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentColor) private var accentColor
    @Environment(\.textOnAccentColor) private var textOnAccentColor
    @Query private var profiles: [UserProfile]
    @Query(sort: \TrainingProgram.name) private var programs: [TrainingProgram]
    
    @State private var selectedDate: Date = Date()
    @State private var showDatePicker = false
    @State private var schedulingSession: SchedulingSessionContext?
    @State private var dragOffset: CGFloat = 0
    
    /// Programme affiché : priorité au programme actif du profil (cohérent avec WorkoutView).
    private var currentProgram: TrainingProgram? {
        profiles.first?.activeTrainingProgram ?? programs.first
    }
    
    private var planningBackground: Color {
        colorScheme == .dark ? PlanningBackgroundDark : Color(.systemGroupedBackground)
    }
    
    /// Cartes : mode clair = gris doux + bordure fine ; dark = #1C1F26.
    private var planningCardBackground: Color {
        colorScheme == .dark ? PlanningCardBg : Color(.secondarySystemGroupedBackground)
    }
    
    private var planningCardBorder: Color {
        colorScheme == .dark ? Color.primary.opacity(0.1) : Color.gray.opacity(0.2)
    }
    
    private var planningVoltColor: Color { accentColor }
    private var planningTextOnVolt: Color { textOnAccentColor }
    /// Texte sur bouton accent : noir en mode clair pour lisibilité sur néons.
    private var planningButtonTextColor: Color { colorScheme == .light ? .black : textOnAccentColor }
    
    private var weekDays: [Date] {
        let cal = Calendar.current
        guard let start = cal.dateInterval(of: .weekOfYear, for: selectedDate)?.start else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
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
            planningBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header: Navigation date + sélecteur L M M J V S D
                dateNavigationHeader
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(colorScheme == .dark ? PlanningCardBg.opacity(0.6) : Color(.systemBackground))
                    .overlay(
                        Rectangle()
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: 0.5),
                        alignment: .bottom
                    )
                
                // Main Content avec gesture de swipe
                ScrollView {
                    VStack(spacing: 20) {
                        if let day = currentTrainingDay {
                            if day.isRestDay {
                                restDayCard(selectedDate: selectedDate)
                            } else if let recipe = day.sessionRecipe {
                                workoutSessionCard(
                                    day: day,
                                    recipe: recipe,
                                    selectedDate: selectedDate,
                                    scheduledTime: storedScheduledTime(date: selectedDate, title: recipe.name),
                                    onPlanifier: {
                                        schedulingSession = SchedulingSessionContext(
                                            title: recipe.name,
                                            durationMinutes: 90,
                                            initialDate: storedScheduledTime(date: selectedDate, title: recipe.name),
                                            excludedEventID: storedCalendarEventID(date: selectedDate, title: recipe.name)
                                        )
                                    }
                                )
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
        .sheet(item: $schedulingSession) { session in
            SchedulingSheet(
                date: selectedDate,
                sessionTitle: session.title,
                durationMinutes: session.durationMinutes,
                initialDate: session.initialDate,
                excludedEventID: session.excludedEventID
            ) { newTime, eventID in
                if let time = newTime {
                    persistScheduledTime(date: selectedDate, title: session.title, time: time)
                    persistCalendarEventID(date: selectedDate, title: session.title, eventID: eventID)
                }
                schedulingSession = nil
            }
        }
    }
    
    // MARK: - Date Navigation Header (Deep Charcoal & Volt)
    
    private var dateNavigationHeader: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                Button {
                    withAnimation(.spring(response: 0.3)) { changeDay(by: -1) }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .ultraLight))
                        .foregroundStyle(Color.primary)
                        .frame(width: 36, height: 36)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Circle())
                }
                Button {
                    showDatePicker = true
                } label: {
                    Text(dateDisplayText)
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                Button {
                    withAnimation(.spring(response: 0.3)) { changeDay(by: 1) }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .ultraLight))
                        .foregroundStyle(Color.primary)
                        .frame(width: 36, height: 36)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Circle())
                }
            }
            // Sélecteur L M M J V S D — jour sélectionné encerclé Volt
            HStack(spacing: 0) {
                ForEach(Array(weekDays.enumerated()), id: \.offset) { index, day in
                    let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDate)
                    Button {
                        withAnimation(.spring(response: 0.3)) { selectedDate = day }
                    } label: {
                        Text(PlanningDayLabels[index])
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(isSelected ? planningVoltColor : Color.secondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().strokeBorder(isSelected ? planningVoltColor : Color.clear, lineWidth: 2))
                    }
                    .frame(maxWidth: .infinity)
                }
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
    
    private func workoutSessionCard(day: TrainingDay, recipe: SessionRecipe, selectedDate: Date, scheduledTime: Date?, onPlanifier: @escaping () -> Void) -> some View {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let selectedStart = calendar.startOfDay(for: selectedDate)
        let isPast = selectedStart < todayStart
        let isToday = calendar.isDateInToday(selectedDate)
        let isFuture = selectedStart > todayStart
        let hasScheduledTime = scheduledTime != nil
        let timeFormatter: DateFormatter = {
            let f = DateFormatter()
            f.timeStyle = .short
            return f
        }()
        return HStack(alignment: .top, spacing: 0) {
            // Décalage aligné avec l'heure du picker (padding.leading 16)
            if scheduledTime != nil { Spacer().frame(width: 16) }
            // Heure Monospaced + ligne Volt verticale (uniquement si heure planifiée)
            if let time = scheduledTime {
                VStack(spacing: 4) {
                    Text(timeFormatter.string(from: time))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(planningVoltColor)
                    Rectangle()
                        .fill(planningVoltColor)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
                .frame(width: 48, alignment: .center)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe.name)
                            .font(.title2.bold())
                            .foregroundStyle(Color.primary)
                        Text(bodyFocusLabel(recipe.bodyFocus))
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    }
                    Spacer()
                }

                // Badge difficulté : capsule bordure accent (Force, Récupération, etc.)
                Text(sessionGoalLabel(recipe.goal))
                    .font(.caption.bold())
                    .foregroundStyle(planningVoltColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .overlay(
                        Capsule().strokeBorder(planningVoltColor, lineWidth: 1.5)
                    )

                if !recipe.exercises.isEmpty {
                    let preview = recipe.exercises.prefix(3).compactMap { $0.exercise?.name }.joined(separator: ", ")
                    let suffix = recipe.exercises.count > 3 ? "..." : ""
                    Text(preview + suffix)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                }

                Divider()
                    .background(Color.primary.opacity(0.1))

                if isPast {
                    Text("Passé")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                } else if isToday {
                    HStack(spacing: 12) {
                        NavigationLink {
                            SessionRunnerView(
                                recipe: recipe,
                                programName: day.week?.program?.name ?? "Programme",
                                weekNumber: day.week?.weekNumber ?? 1,
                                dayIndex: day.dayIndex
                            )
                        } label: {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Lancer la séance")
                                    .font(.headline)
                            }
                            .foregroundStyle(planningButtonTextColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(planningVoltColor)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        Button {
                            onPlanifier()
                        } label: {
                            HStack {
                                Image(systemName: hasScheduledTime ? "clock.arrow.circlepath" : "calendar.badge.clock")
                                Text(hasScheduledTime ? "Modifier l'heure" : "Planifier l'heure")
                                    .font(.headline)
                            }
                            .foregroundStyle(hasScheduledTime ? Color.secondary : planningVoltColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                } else if isFuture {
                    Button {
                        onPlanifier()
                    } label: {
                        HStack {
                            Image(systemName: hasScheduledTime ? "clock.arrow.circlepath" : "calendar.badge.clock")
                            Text(hasScheduledTime ? "Modifier l'heure" : "Planifier l'heure")
                                .font(.headline)
                        }
                        .foregroundStyle(hasScheduledTime ? Color.secondary : planningVoltColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(hasScheduledTime ? Color.primary.opacity(0.08) : planningVoltColor.opacity(0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(planningVoltColor, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .padding(20)
        }
        .background(planningCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(planningCardBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.08), radius: 12, x: 0, y: 4)
        .glow(color: colorScheme == .light ? planningVoltColor : .clear, opacity: 0.3, radius: 20, y: 12)
    }
    
    // MARK: - Rest Day Card (Scenario B)
    
    private func restDayCard(selectedDate: Date) -> some View {
        let calendar = Calendar.current
        let isPast = calendar.startOfDay(for: selectedDate) < calendar.startOfDay(for: Date())

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "bed.double.fill")
                    .font(.title2)
                    .foregroundStyle(planningVoltColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Jour de repos")
                        .font(.title2.bold())
                    Text("Récupération active")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isPast {
                    Text("Passé")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
        .background(planningCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(planningVoltColor.opacity(colorScheme == .dark ? 0.4 : 0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.08), radius: 12, x: 0, y: 4)
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
                .foregroundStyle(planningVoltColor)
                .frame(width: 32, height: 32)
                .background(planningVoltColor.opacity(0.15))
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
                    .foregroundStyle(planningTextOnVolt)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(planningVoltColor)
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
                    .foregroundStyle(planningVoltColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .padding(30)
        .background(planningCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(planningCardBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.08), radius: 12, x: 0, y: 4)
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
        case .lower: return planningVoltColor
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
