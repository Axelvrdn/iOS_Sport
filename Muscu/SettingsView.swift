//
//  SettingsView.swift
//  Muscu
//
//  Centre "Elite Analytics" : résumé profil, graphiques de progression, records personnels, réglages.
//

import SwiftUI
import SwiftData

// MARK: - Routes Paramètres (pour NavigationPath + masquage TabBar)

private enum SettingsRoute: Hashable {
    case profile
    case display
    case exerciseLibrary
    case aiCoach
    case language
    case legal
    case about
}

// MARK: - Elite Analytics Design

private let AnalyticsCardDark = Color(hex: "1C1F26")
private let AnalyticsBgDark = Color(hex: "0F1115")

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

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentColor) private var accentColor
    @Environment(\.tabBarVisibilityStore) private var tabBarVisibilityStore
    @State private var path: [SettingsRoute] = []
    @Query private var profiles: [UserProfile]
    @Query(sort: \WorkoutHistorySession.date, order: .reverse) private var historySessions: [WorkoutHistorySession]
    @Query(sort: \ExerciseSetResult.date, order: .reverse) private var setResults: [ExerciseSetResult]

    private var profile: UserProfile? { profiles.first }
    private var completedSessions: [WorkoutHistorySession] { historySessions.filter(\.isCompleted) }
    private var totalSessionsCount: Int { completedSessions.count }

    private var analyticsBackground: Color {
        colorScheme == .dark ? AnalyticsBgDark : Color(.systemGroupedBackground)
    }
    private var analyticsCardBackground: Color {
        colorScheme == .dark ? AnalyticsCardDark : Color(.secondarySystemGroupedBackground)
    }
    private var chartLineColor: Color { accentColor }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 24) {
                    profileSummaryCard
                    progressionSection
                    personalRecordsSection
                    settingsSection
                }
                .padding(.vertical, 20)
                .padding(.bottom, 40)
            }
            .background(analyticsBackground)
            .navigationTitle("Elite Analytics")
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .profile: ProfileView()
                case .display: DisplaySettingsView()
                case .exerciseLibrary: ExerciseLibraryView()
                case .aiCoach: AICoachSettingsView()
                case .language: LanguageRegionView()
                case .legal: LegalPrivacyView()
                case .about: AboutAppView()
                }
            }
            .onChange(of: path.count) { _, count in
                tabBarVisibilityStore?.isSubPageActive = count > 0
            }
            .onAppear {
                if path.isEmpty {
                    tabBarVisibilityStore?.isSubPageActive = false
                }
            }
        }
    }

    // MARK: - Profil (résumé minimaliste)

    private var profileSummaryCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(chartLineColor)
            VStack(alignment: .leading, spacing: 4) {
                Text("Mon Profil")
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                Text("Niveau \(levelFromSessions)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(totalSessionsCount) séances")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            NavigationLink(value: SettingsRoute.profile) {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(analyticsCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.08) : Color.gray.opacity(0.2), lineWidth: 0.5)
        )
        .padding(.horizontal, 20)
    }

    private var levelFromSessions: Int {
        let n = totalSessionsCount
        if n < 10 { return 1 }
        if n < 30 { return 2 }
        if n < 60 { return 3 }
        return min(4 + (n / 30), 99)
    }

    // MARK: - Progression (graphique Volume)

    private var progressionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progression")
                .font(.headline)
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 4)
            VolumeChartCard(
                sessions: completedSessions,
                lineColor: chartLineColor,
                cardBackground: analyticsCardBackground,
                colorScheme: colorScheme
            )
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Records personnels (top 3)

    private var top3PRs: [(name: String, oneRM: Double, date: Date)] {
        var byExercise: [String: (oneRM: Double, date: Date)] = [:]
        for r in setResults where r.estimatedOneRM > 0 {
            let key = r.exerciseName
            if let existing = byExercise[key] {
                if r.estimatedOneRM > existing.oneRM {
                    byExercise[key] = (r.estimatedOneRM, r.date)
                }
            } else {
                byExercise[key] = (r.estimatedOneRM, r.date)
            }
        }
        return byExercise
            .map { (name: $0.key, oneRM: $0.value.oneRM, date: $0.value.date) }
            .sorted { $0.oneRM > $1.oneRM }
            .prefix(3)
            .map { $0 }
    }

    private var personalRecordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Records personnels")
                .font(.headline)
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 4)
            if top3PRs.isEmpty {
                Text("Aucun record enregistré")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .background(analyticsCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(top3PRs.enumerated()), id: \.offset) { _, pr in
                        PRCard(
                            exerciseName: pr.name,
                            oneRM: pr.oneRM,
                            date: pr.date,
                            cardBackground: analyticsCardBackground,
                            voltColor: chartLineColor,
                            colorScheme: colorScheme
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Réglages (listes épurées)

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Réglages")
                .font(.headline)
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                NavigationLink(value: SettingsRoute.display) {
                    SettingsRow(icon: "paintbrush", iconColor: .orange, title: "Affichage", background: analyticsCardBackground, colorScheme: colorScheme)
                }
                NavigationLink(value: SettingsRoute.exerciseLibrary) {
                    SettingsRow(icon: "book.pages", iconColor: .blue, title: "Bibliothèque d'exercices", background: analyticsCardBackground, colorScheme: colorScheme)
                }
                NavigationLink(value: SettingsRoute.aiCoach) {
                    SettingsRow(icon: "brain.head.profile", iconColor: .purple, title: "AI Coach", background: analyticsCardBackground, colorScheme: colorScheme)
                }
                NavigationLink(value: SettingsRoute.language) {
                    SettingsRow(icon: "globe", iconColor: .green, title: "Langue et Région", background: analyticsCardBackground, colorScheme: colorScheme)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(spacing: 0) {
                NavigationLink(value: SettingsRoute.legal) {
                    SettingsRow(icon: "doc.text", iconColor: .secondary, title: "Mentions légales", background: analyticsCardBackground, colorScheme: colorScheme)
                }
                NavigationLink(value: SettingsRoute.about) {
                    SettingsRow(icon: "info.circle", iconColor: .secondary, title: "À propos", background: analyticsCardBackground, colorScheme: colorScheme)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Carte graphique Volume (ligne Volt + dégradé, interactif)

private struct VolumeChartCard: View {
    let sessions: [WorkoutHistorySession]
    let lineColor: Color
    let cardBackground: Color
    let colorScheme: ColorScheme

    @State private var selectedIndex: Int?

    private var dataPoints: [(date: Date, volume: Double)] {
        let calendar = Calendar.current
        var byDay: [Date: Double] = [:]
        for s in sessions where s.isCompleted {
            let day = calendar.startOfDay(for: s.date)
            byDay[day, default: 0] += s.totalVolumeKg
        }
        return byDay.sorted(by: { $0.key < $1.key }).map { (date: $0.key, volume: $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let idx = selectedIndex, idx >= 0, idx < dataPoints.count {
                let pt = dataPoints[idx]
                Text("\(Int(pt.volume)) kg")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.primary)
                Text(pt.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Volume total")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }
            if dataPoints.isEmpty {
                Text("Aucune donnée")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
            } else {
                VolumeLineChartView(
                    dataPoints: dataPoints,
                    lineColor: lineColor,
                    selectedIndex: $selectedIndex
                )
                .frame(height: 160)
            }
        }
        .padding(20)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.08) : Color.gray.opacity(0.2), lineWidth: 0.5)
        )
    }
}

private struct VolumeLineChartView: View {
    let dataPoints: [(date: Date, volume: Double)]
    let lineColor: Color
    @Binding var selectedIndex: Int?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let maxVol = dataPoints.map(\.volume).max() ?? 1
            let minVol = dataPoints.map(\.volume).min() ?? 0
            let range = max(maxVol - minVol, 1)
            let count = dataPoints.count
            let stepX = count > 1 ? w / CGFloat(count - 1) : w

            ZStack(alignment: .topLeading) {
                // Zone remplie (dégradé sous la courbe)
                if count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: h))
                        for (i, pt) in dataPoints.enumerated() {
                            let x = CGFloat(i) * stepX
                            let y = h - CGFloat((pt.volume - minVol) / range) * (h - 8)
                            if i == 0 { p.addLine(to: CGPoint(x: x, y: y)) }
                            else { p.addLine(to: CGPoint(x: x, y: y)) }
                        }
                        p.addLine(to: CGPoint(x: w, y: h))
                        p.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [lineColor.opacity(0.35), lineColor.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                // Ligne Volt (avec léger glow)
                if count > 1 {
                    Path { p in
                        for (i, pt) in dataPoints.enumerated() {
                            let x = CGFloat(i) * stepX
                            let y = h - CGFloat((pt.volume - minVol) / range) * (h - 8)
                            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                            else { p.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(lineColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .shadow(color: lineColor.opacity(0.4), radius: 4)
                }
                // Grille Y minimaliste (3 repères)
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { i in
                        if i > 0 {
                            Spacer()
                        }
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 0.5)
                            .padding(.horizontal, 8)
                    }
                }
                .frame(height: h - 8)
                .padding(.top, 4)
                // Zone tactile
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let x = value.location.x
                                let idx = count > 1 ? min(max(Int(round(x / stepX)), 0), count - 1) : 0
                                selectedIndex = idx
                            }
                            .onEnded { _ in
                                selectedIndex = nil
                            }
                    )
            }
        }
    }
}

// MARK: - Carte PR (Record personnel)

private struct PRCard: View {
    let exerciseName: String
    let oneRM: Double
    let date: Date
    let cardBackground: Color
    let voltColor: Color
    let colorScheme: ColorScheme

    private var isNewRecord: Bool {
        Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast < date
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(exerciseName)
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Text("\(Int(oneRM)) kg 1RM")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(voltColor)
            }
            Spacer()
            if isNewRecord {
                Text("Nouveau Record")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(voltColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(Capsule().strokeBorder(voltColor, lineWidth: 1))
            }
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.06) : Color.gray.opacity(0.15), lineWidth: 0.5)
        )
    }
}

// MARK: - Ligne de réglage (Label + icône colorée)

private struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let background: Color
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 28, alignment: .center)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(background)
    }
}

// MARK: - Sous-vues (inchangées, navigation)

// MARK: - AI Coach (rigueur, personnalité)

struct AICoachSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.tabBarVisibilityStore) private var tabBarVisibilityStore
    @AppStorage(isAICoachVoiceEnabledKey) private var isVoiceEnabled: Bool = false
    @AppStorage(aiCoachVoiceGenderKey) private var voiceGenderRaw: String = AICoachVoiceGender.female.rawValue
    @AppStorage(localAIEnabledKey) private var localAIEnabled: Bool = false
    @AppStorage(localAIModelDownloadCompletedKey) private var modelDownloadCompleted: Bool = false
    @Query private var profiles: [UserProfile]
    @State private var strictnessLevel: Double = 0.5
    @State private var showAIModelDownloadOverlay: Bool = false

    private var profile: UserProfile? { profiles.first }
    private var voiceGender: Binding<AICoachVoiceGender> {
        Binding(
            get: { AICoachVoiceGender(rawValue: voiceGenderRaw) ?? .female },
            set: { voiceGenderRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Niveau de rigueur du coach")
                        .font(.subheadline.bold())
                    Slider(value: $strictnessLevel, in: 0...1, step: 0.05)
                    HStack {
                        Text("Cool")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Très strict")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Personnalité")
            } footer: {
                Text("Plus le niveau est élevé, plus le coach sera exigeant sur la régularité et la forme.")
            }

            Section {
                Text("Personnalité : \(strictnessLevel < 0.4 ? "Accompagnant" : (strictnessLevel < 0.7 ? "Équilibré" : "Exigeant"))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Activer l'IA Locale (Beta)", isOn: $localAIEnabled)
                if localAIEnabled && !HardwareManager.isLocalAISupported {
                    Label(HardwareManager.unsupportedDeviceMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("IA Locale")
            } footer: {
                Text("Utilise un modèle on-device pour des réponses plus riches. Nécessite au moins 8 Go de RAM (iPhone 15 Pro, M1 ou supérieur). Si désactivé, le coach utilise uniquement le moteur de règles léger.")
            }

            Section {
                Toggle("Synthèse vocale", isOn: $isVoiceEnabled)
                Picker("Voix du coach", selection: voiceGender) {
                    Text("Féminine").tag(AICoachVoiceGender.female)
                    Text("Masculine").tag(AICoachVoiceGender.male)
                }
                .pickerStyle(.menu)
            } header: {
                Text("IA & Voix")
            } footer: {
                Text("Quand la voix est activée, le coach lit à voix haute chaque réponse à la fin de l’affichage.")
            }
        }
        .navigationTitle("AI Coach")
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            tabBarVisibilityStore?.isSubPageActive = true
            strictnessLevel = profile?.strictnessLevel ?? 0.5
        }
        .onDisappear { tabBarVisibilityStore?.isSubPageActive = false }
        .onChange(of: strictnessLevel) { _, newValue in
            profile?.strictnessLevel = newValue
            try? context.save()
        }
        .onChange(of: localAIEnabled) { _, newValue in
            if newValue && !modelDownloadCompleted && HardwareManager.isLocalAISupported {
                showAIModelDownloadOverlay = true
            }
        }
        .fullScreenCover(isPresented: $showAIModelDownloadOverlay) {
            AIModelDownloadView()
                .onDisappear { showAIModelDownloadOverlay = false }
        }
    }
}

// MARK: - Affichage (Premium : grille couleurs, aperçu temps réel, cartes Dark/Light)

private let AccentPresets: [(name: String, hex: String)] = [
    ("Vert Volt", "#D0FD3E"),
    ("Bleu Électrique", "#00B4FF"),
    ("Rouge Feu", "#FF3B30"),
    ("Violet Néon", "#B366FF"),
    ("Blanc Glace", "#E8F4F8")
]

struct DisplaySettingsView: View {
    @AppStorage("useDarkMode") private var useDarkMode: Bool = false
    @AppStorage("useMetricUnits") private var useMetricUnits: Bool = true
    @AppStorage("accentColorHex") private var accentColorHex: String = "#D0FD3E"
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tabBarVisibilityStore) private var tabBarVisibilityStore

    private var pageBackground: Color {
        colorScheme == .dark ? AnalyticsBgDark : Color.white
    }
    private var cardBackground: Color {
        colorScheme == .dark ? AnalyticsCardDark : Color(.secondarySystemGroupedBackground)
    }
    private var cardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.gray.opacity(0.2)
    }
    private var selectedAccent: Color {
        Color(hex: accentColorHex.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                modeSection
                colorSection
                unitsSection
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .background(pageBackground)
        .navigationTitle("Affichage")
        .toolbar(.hidden, for: .tabBar)
        .onAppear { tabBarVisibilityStore?.isSubPageActive = true }
        .onDisappear { tabBarVisibilityStore?.isSubPageActive = false }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mode d'affichage")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                modeCard(isDark: true)
                modeCard(isDark: false)
            }
        }
    }

    private func modeCard(isDark: Bool) -> some View {
        let isSelected = useDarkMode == isDark
        return Button {
            useDarkMode = isDark
        } label: {
            VStack(spacing: 12) {
                Image(systemName: isDark ? "moon.fill" : "sun.max.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(isSelected ? selectedAccent : Color.secondary)
                Text(isDark ? "Sombre" : "Clair")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(isSelected ? selectedAccent : cardBorder, lineWidth: isSelected ? 2 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Couleur d'accent")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 52))], spacing: 16) {
                ForEach(AccentPresets, id: \.hex) { preset in
                    let norm = { (s: String) in s.uppercased().replacingOccurrences(of: "#", with: "") }
                    let isSelected = norm(accentColorHex) == norm(preset.hex)
                    Circle()
                        .fill(Color(hex: preset.hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))))
                        .frame(width: 52, height: 52)
                        .overlay(
                            Circle()
                                .strokeBorder(isSelected ? Color.primary : .clear, lineWidth: 3)
                        )
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) {
                                accentColorHex = preset.hex
                            }
                        }
                }
            }
            miniPreviewCard
            Text("Utilisée pour les boutons, le glow et les accents dans l'app.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var miniPreviewCard: some View {
        HStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(selectedAccent)
                .frame(width: 80, height: 44)
                .overlay(
                    Text("Aperçu")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(selectedAccent.isLight ? .black : .white)
                )
            Spacer()
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(cardBorder, lineWidth: 0.5)
        )
    }

    private var unitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Unités")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                Text("Métriques (kg)")
                    .font(.body)
                    .foregroundStyle(Color.primary)
                Spacer()
                Toggle("", isOn: $useMetricUnits)
                    .labelsHidden()
                    .tint(selectedAccent)
            }
            .padding(16)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(cardBorder, lineWidth: 0.5)
            )
            Text("Désactiver pour afficher les poids en livres (lbs).")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

private extension Color {
    var isLight: Bool {
        let comps = (UIColor(self).cgColor.components ?? []).prefix(3).map { Double($0) }
        guard comps.count >= 3 else { return false }
        let (r, g, b) = (comps[0], comps[1], comps[2])
        return (r * 0.299 + g * 0.587 + b * 0.114) > 0.6
    }
}

// MARK: - Langue et Région (fond unifié, sections 20pt)

struct LanguageRegionView: View {
    @Environment(\.tabBarVisibilityStore) private var tabBarVisibilityStore
    @Environment(\.colorScheme) private var colorScheme

    private var pageBackground: Color {
        colorScheme == .dark ? AnalyticsBgDark : Color.white
    }
    private var cardBackground: Color {
        colorScheme == .dark ? AnalyticsCardDark : Color(.secondarySystemGroupedBackground)
    }
    private var cardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.gray.opacity(0.2)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                unifiedSection(title: "Langue") {
                    Text("La langue de l'application suit celle de ton appareil.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                unifiedSection(title: "Région") {
                    Text("Région : \(Locale.current.region?.identifier ?? "—")")
                        .font(.subheadline)
                        .foregroundStyle(Color.primary)
                }
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .background(pageBackground)
        .navigationTitle("Langue et Région")
        .toolbar(.hidden, for: .tabBar)
        .onAppear { tabBarVisibilityStore?.isSubPageActive = true }
        .onDisappear { tabBarVisibilityStore?.isSubPageActive = false }
    }

    private func unifiedSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(cardBorder, lineWidth: 0.5)
                )
        }
    }
}

// MARK: - Mentions Légales & Confidentialité (fond unifié, sections 20pt)

struct LegalPrivacyView: View {
    @Environment(\.tabBarVisibilityStore) private var tabBarVisibilityStore
    @Environment(\.colorScheme) private var colorScheme

    private var pageBackground: Color {
        colorScheme == .dark ? AnalyticsBgDark : Color.white
    }
    private var cardBackground: Color {
        colorScheme == .dark ? AnalyticsCardDark : Color(.secondarySystemGroupedBackground)
    }
    private var cardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.gray.opacity(0.2)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Mentions légales")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Muscu est une application de suivi d'entraînement. Les données sont stockées localement sur ton appareil.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(cardBorder, lineWidth: 0.5)
                        )
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Confidentialité")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Nous ne collectons pas de données personnelles à des fins commerciales. Tes données restent sur ton appareil.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(cardBorder, lineWidth: 0.5)
                        )
                }
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .background(pageBackground)
        .navigationTitle("Mentions Légales & Confidentialité")
        .toolbar(.hidden, for: .tabBar)
        .onAppear { tabBarVisibilityStore?.isSubPageActive = true }
        .onDisappear { tabBarVisibilityStore?.isSubPageActive = false }
    }
}

// MARK: - À propos (fond unifié, sections 20pt)

struct AboutAppView: View {
    @Environment(\.tabBarVisibilityStore) private var tabBarVisibilityStore
    @Environment(\.colorScheme) private var colorScheme

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
    private var buildNumber: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    }
    private var pageBackground: Color {
        colorScheme == .dark ? AnalyticsBgDark : Color.white
    }
    private var cardBackground: Color {
        colorScheme == .dark ? AnalyticsCardDark : Color(.secondarySystemGroupedBackground)
    }
    private var cardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.gray.opacity(0.2)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Version")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("\(appVersion) (\(buildNumber))")
                            .font(.subheadline)
                            .foregroundStyle(Color.primary)
                        Spacer()
                    }
                    .padding(16)
                    .background(cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(cardBorder, lineWidth: 0.5)
                    )
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("À propos")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Muscu — Suivi d'entraînement et programmes personnalisables.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(cardBorder, lineWidth: 0.5)
                        )
                }
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .background(pageBackground)
        .navigationTitle("À propos")
        .toolbar(.hidden, for: .tabBar)
        .onAppear { tabBarVisibilityStore?.isSubPageActive = true }
        .onDisappear { tabBarVisibilityStore?.isSubPageActive = false }
    }
}
