//
//  ProfileView.swift
//  Muscu
//
//  Rôle : Tableau de bord profil utilisateur (objectifs, style, disponibilités, liquid glass).
//  Utilisé par : SettingsView (NavigationLink Profil).
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - Helpers pour l'affichage

extension PhysiqueGoal {
    var displayName: String {
        switch self {
        case .cut: return "Sèche"
        case .maintain: return "Maintien"
        case .bulk: return "Prise de masse"
        }
    }
    var iconName: String {
        switch self {
        case .cut: return "flame"
        case .maintain: return "scalemass"
        case .bulk: return "arrow.up.circle"
        }
    }
}

extension SpecificSport {
    var displayName: String {
        switch self {
        case .boxing: return "Boxe"
        case .volley: return "Volley"
        case .basket: return "Basket"
        }
    }
}

extension InjurySensitivity {
    var displayName: String {
        switch self {
        case .low: return "Faible"
        case .medium: return "Moyenne"
        case .high: return "Élevée"
        }
    }
}

// NOTE: `TrainingStyleKind` a été déplacé dans `TrainingStyleKind.swift` (utilisé par l'onboarding).

// MARK: - Disponibilité hebdo (7 jours) — lié à UserProfile.availableDays

// Legacy: anciens labels de jours (L M M J V S D) supprimés avec le planning global.
// private let dayLabels = ["L", "M", "M", "J", "V", "S", "D"]

// MARK: - DoubleTapEditableField (lecture / édition au double-tap)

struct DoubleTapEditableIntField: View {
    @Binding var value: Int
    var label: String
    var range: ClosedRange<Int>
    var onCommit: (() -> Void)?

    @State private var isEditing = false
    @State private var textValue: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            if isEditing {
                TextField("", text: $textValue)
                    .keyboardType(.numberPad)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .focused($isFocused)
                    .onSubmit { commitInt() }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commitInt() }
                    }
            } else {
                HStack(spacing: 4) {
                    Text("\(value)")
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                    Image(systemName: "pencil.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.8))
                }
                .onTapGesture(count: 2) {
                    textValue = "\(value)"
                    isEditing = true
                    isFocused = true
                }
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .onAppear { textValue = "\(value)" }
    }

    private func commitInt() {
        let parsed = Int(textValue).map { min(max($0, range.lowerBound), range.upperBound) } ?? value
        value = parsed
        isEditing = false
        isFocused = false
        onCommit?()
    }
}

struct DoubleTapEditableDoubleField: View {
    @Binding var value: Double
    var label: String
    var range: ClosedRange<Double>
    var step: Double
    var onCommit: (() -> Void)?

    @State private var isEditing = false
    @State private var textValue: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            if isEditing {
                TextField("", text: $textValue)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .focused($isFocused)
                    .onSubmit { commitDouble() }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commitDouble() }
                    }
            } else {
                HStack(spacing: 4) {
                    Text(step >= 1 ? "\(Int(value))" : String(format: "%.1f", value))
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                    Image(systemName: "pencil.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.8))
                }
                .onTapGesture(count: 2) {
                    textValue = step >= 1 ? "\(Int(value))" : String(format: "%.1f", value)
                    isEditing = true
                    isFocused = true
                }
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .onAppear { textValue = step >= 1 ? "\(Int(value))" : String(format: "%.1f", value) }
    }

    private func commitDouble() {
        let parsed = Double(textValue.replacingOccurrences(of: ",", with: "."))
        let clamped = parsed.map { min(max($0, range.lowerBound), range.upperBound) } ?? value
        value = clamped
        isEditing = false
        isFocused = false
        onCommit?()
    }
}

// MARK: - Couleurs Elite Profile (fond unifié, cartes)

private let EliteProfileBgDark = Color(red: 15/255, green: 17/255, blue: 21/255)
private let EliteProfileCardDark = Color(red: 28/255, green: 31/255, blue: 38/255)

// MARK: - Badges Elite (Honneurs)

private enum EliteProfileBadge: String, CaseIterable {
    case firstSession = "figure.strengthtraining.traditional"
    case consistency = "flame"
    case ecouteDuCorps = "shield.fill"
    case volume = "dumbbell.fill"

    var iconName: String { rawValue }

    var displayName: String {
        switch self {
        case .firstSession: return "PREMIÈRE SÉANCE"
        case .consistency: return "MAÎTRE DE LA RÉGULARITÉ"
        case .ecouteDuCorps: return "ÉCOUTE DU CORPS"
        case .volume: return "MAÎTRE DU VOLUME"
        }
    }

    var criteriaDescription: String {
        switch self {
        case .firstSession: return "Attribué pour avoir complété ta première séance d'entraînement. Le début d'une aventure."
        case .consistency: return "Attribué pour avoir enchaîné au moins 3 jours d'entraînement sur les 7 derniers jours. La régularité prime."
        case .ecouteDuCorps: return "Attribué pour avoir renseigné tes blessures ou ta sensibilité dans le profil santé. Valoriser la prévention et l'écoute de son corps."
        case .volume: return "Attribué pour avoir complété 10 séances. La constance récompensée."
        }
    }

    func isAcquired(profile: UserProfile?, historySessions: [WorkoutHistorySession], injuryHistory: String, injurySensitivity: InjurySensitivity) -> Bool {
        let completed = historySessions.filter(\.isCompleted)
        switch self {
        case .firstSession:
            return !completed.isEmpty
        case .consistency:
            let calendar = Calendar.current
            let last7 = (0..<7).compactMap { calendar.date(byAdding: .day, value: -$0, to: Date()) }
            let daysWithSession = Set(last7.compactMap { d in completed.first(where: { calendar.isDate($0.date, inSameDayAs: d) }).map { _ in d } })
            return daysWithSession.count >= 3
        case .ecouteDuCorps:
            return !injuryHistory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || injurySensitivity != .medium
        case .volume:
            return completed.count >= 10
        }
    }

    func acquiredDate(historySessions: [WorkoutHistorySession]) -> Date? {
        let completed = historySessions.filter(\.isCompleted).sorted(by: { $0.date < $1.date })
        switch self {
        case .firstSession: return completed.first?.date
        case .volume: return completed.count >= 10 ? completed[9].date : nil
        case .consistency:
            let calendar = Calendar.current
            let last7 = (0..<7).compactMap { calendar.date(byAdding: .day, value: -$0, to: Date()) }
            let daysWithSession = last7.filter { d in completed.contains(where: { calendar.isDate($0.date, inSameDayAs: d) }) }
            return daysWithSession.count >= 3 ? daysWithSession.sorted().last : nil
        case .ecouteDuCorps: return nil
        }
    }
}

/// Item pour la modale détail (Identifiable pour .sheet(item:)).
private struct BadgeDetailItem: Identifiable {
    var id: EliteProfileBadge { badge }
    let badge: EliteProfileBadge
    let isAcquired: Bool
    let acquiredDate: Date?
}

private struct HonneurBadgeView: View {
    let badge: EliteProfileBadge
    let isAcquired: Bool
    let accentColor: Color
    let borderColor: Color
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            onTap?()
        } label: {
            Circle()
                .fill(isAcquired ? accentColor.opacity(0.2) : Color.clear)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: badge.iconName)
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(isAcquired ? accentColor : Color.gray.opacity(0.5))
                )
                .overlay(
                    Circle()
                        .strokeBorder(isAcquired ? accentColor.opacity(0.6) : borderColor, lineWidth: isAcquired ? 1.2 : 0.8)
                )
                .shadow(color: isAcquired ? accentColor.opacity(0.35) : .clear, radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - BadgeDetailView (modale stylisée, glassmorphism, detents)

private struct BadgeDetailView: View {
    let item: BadgeDetailItem
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentColor) private var accentColor
    @Environment(\.dismiss) private var dismiss

    private var formattedAcquiredDate: String? {
        guard let d = item.acquiredDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: d)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: item.badge.iconName)
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(item.isAcquired ? accentColor : Color.gray.opacity(0.5))
                    .shadow(color: item.isAcquired ? accentColor.opacity(0.6) : .clear, radius: 20, y: 4)
                    .glow(color: accentColor, opacity: item.isAcquired ? (colorScheme == .dark ? 0.5 : 0.35) : 0, radius: item.isAcquired ? 24 : 0, y: 6)

                Text(item.badge.displayName)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.center)

                if item.isAcquired, let dateStr = formattedAcquiredDate {
                    Text("Acquis le \(dateStr)")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.secondary)
                } else {
                    Text("En cours...")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(accentColor)
                }

                Text(item.badge.criteriaDescription)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)

                Spacer(minLength: 8)
            }
            .padding(.top, 32)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Sheet édition statut (âge, poids, objectif)

private struct EditStatutSheet: View {
    @Binding var age: Int
    @Binding var weight: Double
    @Binding var weightGoal: Double
    @Binding var selectedPhysiqueGoal: PhysiqueGoal
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Âge : \(age)", value: $age, in: 10...90)
                    Stepper("Poids : \(Int(weight)) kg", value: $weight, in: 40...150, step: 1)
                    Stepper("Objectif poids : \(Int(weightGoal)) kg", value: $weightGoal, in: 40...150, step: 1)
                }
                Section("Objectif physique") {
                    Picker("", selection: $selectedPhysiqueGoal) {
                        ForEach(PhysiqueGoal.allCases, id: \.self) { goal in
                            Text(goal.displayName).tag(goal)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Modifier mon statut")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Carte Elite (fond #1C1F26 / blanc, coins 20pt)

private struct EliteProfileCardModifier: ViewModifier {
    var background: Color
    var border: Color
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(border, lineWidth: 0.5)
            )
    }
}

extension View {
    fileprivate func eliteProfileCard(background: Color, border: Color, cornerRadius: CGFloat = 18) -> some View {
        modifier(EliteProfileCardModifier(background: background, border: border, cornerRadius: cornerRadius))
    }
}


// MARK: - Profile View (Elite Athlete Dashboard)

struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentColor) private var accentColor
    @Environment(\.textOnAccentColor) private var textOnAccentColor
    @Environment(\.tabBarVisibilityStore) private var tabBarVisibilityStore
    @Query private var profiles: [UserProfile]
    @Query(sort: \WorkoutHistorySession.date, order: .reverse) private var historySessions: [WorkoutHistorySession]
    @State private var age: Int = 25
    @State private var weight: Double = 70
    @State private var selectedPhysiqueGoal: PhysiqueGoal = .maintain
    @State private var injuryHistory: String = ""
    @State private var injurySensitivity: InjurySensitivity = .medium
    @State private var sportsHistory: String = ""
    @State private var currentOtherSports: String = ""
    @State private var weightGoal: Double = 75
    @State private var strictnessLevel: Double = 0.5
    @State private var selectedDisciplines: Set<Discipline> = [.strength]
    @State private var hasGymAccess: Bool = true
    @State private var didLoadExistingProfile = false
    @State private var saveMessage: String?

    /// Planning par discipline (éditable dans le profil, source de vérité UI).
    @State private var disciplineSchedule: [Discipline: Set<DayOfWeek>] = [:]

    private let dayOrder: [(day: DayOfWeek, short: String, label: String)] = [
        (.monday, "L", "Lundi"),
        (.tuesday, "M", "Mardi"),
        (.wednesday, "M", "Mercredi"),
        (.thursday, "J", "Jeudi"),
        (.friday, "V", "Vendredi"),
        (.saturday, "S", "Samedi"),
        (.sunday, "D", "Dimanche")
    ]

    private var eliteBackground: Color {
        colorScheme == .dark ? EliteProfileBgDark : Color.white
    }
    private var eliteCardBackground: Color {
        colorScheme == .dark ? EliteProfileCardDark : Color(.secondarySystemGroupedBackground)
    }
    private var eliteCardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.gray.opacity(0.2)
    }

    /// Intensité du glow de l'avatar : plus forte si activité récente (séance complétée dans les 7 derniers jours).
    private var hasRecentActivity: Bool {
        let calendar = Calendar.current
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) else { return false }
        return historySessions.contains { $0.isCompleted && $0.date >= weekAgo }
    }

    @State private var showEditStatutSheet: Bool = false
    @State private var isStrategieExpanded: Bool = false
    @State private var isSanteExpanded: Bool = false
    @State private var selectedBadge: BadgeDetailItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                eliteHeader
                statutLine
                honneursSection
                expandableStrategieCard
                expandableSanteCard
                if let message = saveMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                saveButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
        .background(eliteBackground)
        .navigationTitle("Mon Profil")
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showEditStatutSheet) {
            EditStatutSheet(age: $age, weight: $weight, weightGoal: $weightGoal, selectedPhysiqueGoal: $selectedPhysiqueGoal, onSave: persistProfileMetrics)
        }
        .sheet(item: $selectedBadge) { item in
            BadgeDetailView(item: item)
        }
        .onAppear {
            tabBarVisibilityStore?.isSubPageActive = true
            loadExistingProfileIfNeeded()
        }
        .onDisappear {
            tabBarVisibilityStore?.isSubPageActive = false
        }
    }

    // MARK: - 1. Header Athlète (avatar + glow selon activité récente)

    private var eliteHeader: some View {
        VStack(spacing: 12) {
            Circle()
                .strokeBorder(accentColor, lineWidth: 1.2)
                .background(Circle().fill(eliteCardBackground))
                .frame(width: 76, height: 76)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(accentColor.opacity(0.9))
                )
                .glow(
                    color: accentColor,
                    opacity: hasRecentActivity ? (colorScheme == .dark ? 0.5 : 0.35) : (colorScheme == .dark ? 0.25 : 0.15),
                    radius: hasRecentActivity ? 18 : 12,
                    y: 4
                )

            Text("Mon Profil")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// Section "Statut" : une ligne minimaliste "20 ans • 70 kg • Objectif : Maintien". Tap pour modifier.
    private var statutLine: some View {
        Button {
            showEditStatutSheet = true
        } label: {
            HStack(spacing: 6) {
                Text("\(age) ans")
                    .font(.system(.subheadline, design: .monospaced))
                Text("•")
                    .foregroundStyle(.secondary)
                Text("\(Int(weight)) kg")
                    .font(.system(.subheadline, design: .monospaced))
                Text("•")
                    .foregroundStyle(.secondary)
                Text("Objectif : \(selectedPhysiqueGoal.displayName)")
                    .font(.system(.subheadline, design: .rounded))
                Spacer(minLength: 4)
                Image(systemName: "pencil.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(Color.primary)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(eliteCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(eliteCardBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Honneurs (badges Elite Achievements, interactifs + modale détail)

    private var honneursSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Honneurs")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(EliteProfileBadge.allCases, id: \.self) { badge in
                        let isAcquired = badge.isAcquired(profile: profiles.first, historySessions: historySessions, injuryHistory: injuryHistory, injurySensitivity: injurySensitivity)
                        HonneurBadgeView(
                            badge: badge,
                            isAcquired: isAcquired,
                            accentColor: accentColor,
                            borderColor: eliteCardBorder,
                            onTap: {
                                selectedBadge = BadgeDetailItem(
                                    badge: badge,
                                    isAcquired: isAcquired,
                                    acquiredDate: badge.acquiredDate(historySessions: historySessions)
                                )
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Mon Profil Athlétique
    // (Supprimée) : la sélection des disciplines est désormais intégrée dans "Ma Stratégie".

    /// Sauvegarde âge / poids / objectif dans le profil SwiftData (sans tout le formulaire).
    private func persistProfileMetrics() {
        guard let profile = profiles.first else { return }
        profile.age = age
        profile.weight = weight
        profile.weightGoal = weightGoal
        try? context.save()
    }

    // MARK: - Cartes expandables (résumé par défaut, coins 20pt)

    private var strategieSummaryText: String {
        if selectedDisciplines.isEmpty {
            return "Aucune discipline sélectionnée"
        }
        let names = selectedDisciplines.map { $0.displayName }.joined(separator: " · ")
        return hasGymAccess ? "\(names) • Accès salle" : "\(names) • No‑Gym"
    }

    private var expandableStrategieCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isStrategieExpanded.toggle()
                }
            } label: {
                HStack {
                    Label("Ma Stratégie", systemImage: "target")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .symbolVariant(.none)
                    Spacer()
                    Text(isStrategieExpanded ? "" : strategieSummaryText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: isStrategieExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .buttonStyle(.plain)

            if isStrategieExpanded {
                VStack(alignment: .leading, spacing: 18) {
                    Divider().background(eliteCardBorder)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Objectif physique")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(PhysiqueGoal.allCases, id: \.self) { goal in
                                physiqueGoalCapsule(goal)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mes Disciplines (max 3)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                            ForEach(Discipline.allCases) { d in
                                disciplineCapsule(d)
                            }
                        }

                        if disciplineConflictWarning != nil {
                            Text(disciplineConflictWarning!)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Toggle("Accès à une salle de sport", isOn: $hasGymAccess)
                        .font(.subheadline)
                    if !selectedDisciplines.isEmpty {
                        planningSection
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .eliteProfileCard(background: eliteCardBackground, border: eliteCardBorder, cornerRadius: 20)
    }

    private func physiqueGoalCapsule(_ goal: PhysiqueGoal) -> some View {
        let isSelected = selectedPhysiqueGoal == goal
        return Button {
            selectedPhysiqueGoal = goal
        } label: {
            HStack(spacing: 6) {
                Image(systemName: goal.iconName)
                    .font(.subheadline.weight(.semibold))
                Text(goal.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? accentColor.opacity(0.25) : Color.clear)
            .foregroundStyle(isSelected ? accentColor : Color.primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? accentColor.opacity(0.6) : eliteCardBorder, lineWidth: isSelected ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func disciplineCapsule(_ d: Discipline) -> some View {
        let isSelected = selectedDisciplines.contains(d)
        return Button {
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.prepare()
            if isSelected {
                selectedDisciplines.remove(d)
                disciplineSchedule[d] = nil
            } else if selectedDisciplines.count < 3 {
                selectedDisciplines.insert(d)
            } else {
                generator.impactOccurred(intensity: 0.9)
            }
        } label: {
            Text("\(d.emoji) \(d.displayName)")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(isSelected ? accentColor.opacity(0.25) : Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04))
                .foregroundStyle(isSelected ? accentColor : Color.primary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? accentColor.opacity(0.6) : eliteCardBorder, lineWidth: isSelected ? 1 : 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private var disciplineConflictWarning: String? {
        let d = selectedDisciplines
        if d.contains(.combat) && d.contains(.ballSports) {
            return "Attention : Combat + Sports de ballon = forte contrainte épaules/genoux. Prévois préhab & deload."
        }
        return nil
    }

    /// Sélecteur de jours par discipline (planning éditable).
    private var planningSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Planning par discipline")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            let discs = selectedDisciplines.sorted { $0.displayName < $1.displayName }

            ForEach(discs, id: \.self) { discipline in
                disciplineScheduleRow(for: discipline)
            }
        }
    }

    private func disciplineScheduleRow(for discipline: Discipline) -> some View {
        let selectedSet = disciplineSchedule[discipline] ?? []
        let occupiedByOthers: Set<DayOfWeek> = disciplineSchedule
            .filter { $0.key != discipline }
            .values
            .reduce(into: Set<DayOfWeek>()) { acc, set in acc.formUnion(set) }

        return VStack(alignment: .leading, spacing: 6) {
            Text("\(discipline.emoji) \(discipline.displayName)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                ForEach(dayOrder, id: \.day) { info in
                    dayChip(
                        day: info.day,
                        short: info.short,
                        label: info.label,
                        discipline: discipline,
                        selectedSet: selectedSet,
                        occupiedByOthers: occupiedByOthers
                    )
                }
            }
        }
    }

    private func dayChip(
        day: DayOfWeek,
        short: String,
        label: String,
        discipline: Discipline,
        selectedSet: Set<DayOfWeek>,
        occupiedByOthers: Set<DayOfWeek>
    ) -> some View {
        let isDisabled = occupiedByOthers.contains(day)
        let isSelected = selectedSet.contains(day)

        return Button {
            guard !isDisabled else { return }
            var updated = selectedSet
            if updated.contains(day) {
                updated.remove(day)
            } else {
                updated.insert(day)
            }
            disciplineSchedule[discipline] = updated
        } label: {
            VStack(spacing: 3) {
                Text(short)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Circle()
                    .fill(
                        isDisabled
                        ? Color.secondary.opacity(0.1)
                        : (isSelected ? accentColor : Color.clear)
                    )
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isDisabled
                                ? eliteCardBorder
                                : (isSelected ? accentColor : eliteCardBorder),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
            }
            .foregroundStyle(
                isDisabled
                ? Color.secondary.opacity(0.4)
                : (isSelected ? accentColor : Color.primary)
            )
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private var santeSummaryText: String {
        if !injuryHistory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Santé : blessures renseignées"
        }
        if !sportsHistory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Santé : historique renseigné"
        }
        return "Santé : à compléter"
    }

    private var expandableSanteCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isSanteExpanded.toggle()
                }
            } label: {
                HStack {
                    Label("Mon Profil Santé", systemImage: "heart.text.square")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .symbolVariant(.none)
                    Spacer()
                    Text(isSanteExpanded ? "" : santeSummaryText)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: isSanteExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .buttonStyle(.plain)

            if isSanteExpanded {
                VStack(alignment: .leading, spacing: 18) {
                    Divider().background(eliteCardBorder)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Blessures & Antécédents")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $injuryHistory)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 72)
                            .padding(10)
                            .background(Color(.tertiarySystemFill).opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(eliteCardBorder, lineWidth: 0.5)
                            )
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sensibilité aux blessures")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Picker("", selection: $injurySensitivity) {
                            ForEach(InjurySensitivity.allCases, id: \.self) { level in
                                Text(level.displayName).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Historique sportif")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $sportsHistory)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 52)
                            .padding(10)
                            .background(Color(.tertiarySystemFill).opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(eliteCardBorder, lineWidth: 0.5)
                            )
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sports actuels parallèles")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $currentOtherSports)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 44)
                            .padding(10)
                            .background(Color(.tertiarySystemFill).opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(eliteCardBorder, lineWidth: 0.5)
                            )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .eliteProfileCard(background: eliteCardBackground, border: eliteCardBorder, cornerRadius: 20)
    }

    private var saveButton: some View {
        VStack(spacing: 12) {
            Button(action: saveProfile) {
                Text("Enregistrer le profil")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(accentColor)
                    .foregroundStyle(textOnAccentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)

            Button {
                DataController.generatePersonalizedProgram(context: context, force: true)
            } label: {
                Text("Réinitialiser mon programme")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(accentColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(accentColor.opacity(0.6), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 28)
        .padding(.bottom, 12)
    }

    // MARK: - Chargement & Sauvegarde

    private func loadExistingProfileIfNeeded() {
        guard !didLoadExistingProfile,
              let profile = profiles.first else { return }

        didLoadExistingProfile = true
        age = profile.age
        weight = profile.weight
        selectedPhysiqueGoal = profile.physiqueGoal
        injuryHistory = profile.injuryHistory
        injurySensitivity = profile.injurySensitivity
        sportsHistory = profile.sportsHistory
        currentOtherSports = profile.currentOtherSports
        weightGoal = profile.weightGoal
        strictnessLevel = profile.strictnessLevel
        selectedDisciplines = profile.selectedDisciplines
        hasGymAccess = profile.hasGymAccess
        disciplineSchedule = profile.disciplineSchedule
    }

    private func saveProfile() {
        let profile: UserProfile
        if let existing = profiles.first {
            profile = existing
        } else {
            profile = UserProfile()
            context.insert(profile)
        }

        profile.age = age
        profile.weight = weight
        profile.physiqueGoal = selectedPhysiqueGoal
        profile.injuryHistory = injuryHistory
        profile.injurySensitivity = injurySensitivity
        profile.sportsHistory = sportsHistory
        profile.currentOtherSports = currentOtherSports
        profile.weightGoal = weightGoal
        profile.strictnessLevel = strictnessLevel
        profile.selectedDisciplines = selectedDisciplines
        profile.hasGymAccess = hasGymAccess
        profile.disciplineSchedule = disciplineSchedule

        do {
            try context.save()
            saveMessage = "Profil enregistré."
        } catch {
            saveMessage = "Erreur lors de l'enregistrement."
        }
    }
}
