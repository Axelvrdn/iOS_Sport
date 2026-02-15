//
//  ProfileView.swift
//  Muscu
//
//  Tableau de bord personnel : cartes modernes (liquid glass), synthèse et sections.
//

import SwiftUI
import SwiftData

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
}

// MARK: - Disponibilité hebdo (7 jours) — lié à UserProfile.availableDays

private let dayLabels = ["L", "M", "M", "J", "V", "S", "D"]

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
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .focused($isFocused)
                    .onSubmit { commitInt() }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commitInt() }
                    }
            } else {
                HStack(spacing: 4) {
                    Text("\(value)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
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
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .focused($isFocused)
                    .onSubmit { commitDouble() }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commitDouble() }
                    }
            } else {
                HStack(spacing: 4) {
                    Text(step >= 1 ? "\(Int(value))" : String(format: "%.1f", value))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
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

// MARK: - Profile View (Dashboard par cartes)

struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @StateObject private var healthKit = HealthKitManager.shared
    @AppStorage("healthKitAutoSync") private var healthKitAutoSync: Bool = true

    @State private var age: Int = 25
    @State private var weight: Double = 70
    @State private var selectedPhysiqueGoal: PhysiqueGoal = .maintain
    @State private var trainingStyleKind: TrainingStyleKind = .bodybuilding
    @State private var specificSport: SpecificSport = .boxing
    @State private var injuryHistory: String = ""
    @State private var injurySensitivity: InjurySensitivity = .medium
    @State private var sessionsPerWeek: Int = 3
    @State private var hoursPerSession: Double = 1.0
    @State private var sportsHistory: String = ""
    @State private var currentOtherSports: String = ""
    @State private var weightGoal: Double = 75
    @State private var strictnessLevel: Double = 0.5
    @State private var availabilityDays: [Bool] = Array(repeating: true, count: 7)
    @State private var didLoadExistingProfile = false
    @State private var saveMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard
                    objectifsCard
                    logistiqueCard
                    contexteSanteCard
                    saveButton
                    if let message = saveMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Mon Profil")
            .onAppear {
                loadExistingProfileIfNeeded()
                Task { await syncFromHealthKitIfNeeded() }
            }
        }
    }

    // MARK: - 1. En-tête de synthèse

    private var headerCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue.opacity(0.8), .purple.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            HStack(spacing: 0) {
                DoubleTapEditableIntField(value: $age, label: "Âge", range: 10...90) { persistProfileMetrics() }
                Divider()
                    .frame(height: 44)
                DoubleTapEditableDoubleField(value: $weight, label: "Poids actuel (kg)", range: 40...150, step: 1) { persistProfileMetrics() }
                Divider()
                    .frame(height: 44)
                DoubleTapEditableDoubleField(value: $weightGoal, label: "Objectif (kg)", range: 40...150, step: 1) { persistProfileMetrics() }
            }
            .padding(.vertical, 8)
        }
        .padding()
        .dashboardCard()
    }

    /// Sauvegarde âge / poids / objectif dans le profil SwiftData (sans tout le formulaire).
    private func persistProfileMetrics() {
        guard let profile = profiles.first else { return }
        profile.age = age
        profile.weight = weight
        profile.weightGoal = weightGoal
        try? context.save()
    }

    /// Récupère âge et poids depuis HealthKit et remplit les champs si vides ou si Auto-Sync activé.
    private func syncFromHealthKitIfNeeded() async {
        await healthKit.requestAuthorization()
        await healthKit.fetchProfileData()
        guard healthKitAutoSync || age == 0 || weight == 0 else { return }
        if let hkAge = healthKit.healthKitAge, (age == 0 || healthKitAutoSync) {
            age = min(90, max(10, hkAge))
        }
        if let hkWeight = healthKit.healthKitWeight, (weight == 0 || healthKitAutoSync) {
            weight = min(150, max(40, hkWeight))
        }
        await MainActor.run { persistProfileMetrics() }
    }

    // MARK: - 2. Objectifs & Stratégie

    private var objectifsCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Objectifs & Stratégie")
                .font(.headline.bold())

            VStack(alignment: .leading, spacing: 10) {
                Text("Objectif physique")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(PhysiqueGoal.allCases, id: \.self) { goal in
                        physiqueGoalButton(goal)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Style d'entraînement")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(TrainingStyleKind.allCases) { kind in
                        trainingStyleButton(kind)
                    }
                }
                if trainingStyleKind == .specificSport {
                    Picker("Sport", selection: $specificSport) {
                        ForEach(SpecificSport.allCases, id: \.self) { sport in
                            Text(sport.displayName).tag(sport)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .padding()
        .dashboardCard()
    }

    private func physiqueGoalButton(_ goal: PhysiqueGoal) -> some View {
        let isSelected = selectedPhysiqueGoal == goal
        return Button {
            selectedPhysiqueGoal = goal
        } label: {
            VStack(spacing: 6) {
                Image(systemName: goal.iconName)
                    .font(.title2)
                Text(goal.displayName)
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func trainingStyleButton(_ kind: TrainingStyleKind) -> some View {
        let isSelected = trainingStyleKind == kind
        return Button {
            trainingStyleKind = kind
        } label: {
            HStack(spacing: 8) {
                Image(systemName: kind.iconName)
                    .font(.body)
                Text(kind.displayName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 3. Logistique & Disponibilités

    private var logistiqueCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Logistique & Disponibilités")
                .font(.headline.bold())

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Séances / semaine")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    Stepper("\(sessionsPerWeek)", value: $sessionsPerWeek, in: 1...14)
                        .labelsHidden()
                    Text("\(sessionsPerWeek)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Heures / séance")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    Stepper("\(hoursPerSession, specifier: "%.1f") h", value: $hoursPerSession, in: 0.5...3, step: 0.5)
                        .labelsHidden()
                    Text("\(hoursPerSession, specifier: "%.1f") h")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Disponibilité hebdomadaire")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    ForEach(0..<7, id: \.self) { index in
                        dayBubble(index: index)
                    }
                }
            }
        }
        .padding()
        .dashboardCard()
    }

    private func dayBubble(index: Int) -> some View {
        let isAvailable = availabilityDays.indices.contains(index) && availabilityDays[index]
        return Button {
            if availabilityDays.indices.contains(index) {
                availabilityDays[index].toggle()
            }
        } label: {
            Text(dayLabels[index])
                .font(.caption.bold())
                .frame(width: 36, height: 36)
                .background(isAvailable ? Color.accentColor.opacity(0.3) : Color(.tertiarySystemFill))
                .foregroundStyle(isAvailable ? Color.accentColor : Color.secondary)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color.secondary.opacity(isAvailable ? 0.2 : 0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 4. Contexte Santé & Passif

    private var contexteSanteCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Contexte Santé & Passif")
                .font(.headline.bold())

            VStack(alignment: .leading, spacing: 8) {
                Text("Blessures & Antécédents")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                TextEditor(text: $injuryHistory)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80)
                    .padding(12)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Sensibilité aux blessures")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Picker("", selection: $injurySensitivity) {
                    ForEach(InjurySensitivity.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Historique sportif")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                TextEditor(text: $sportsHistory)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 60)
                    .padding(12)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Sports actuels parallèles")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                TextEditor(text: $currentOtherSports)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 50)
                    .padding(12)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
        }
        .padding()
        .dashboardCard()
    }

    private var saveButton: some View {
        Button(action: saveProfile) {
            Text("Enregistrer le profil")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
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
        sessionsPerWeek = profile.sessionsPerWeek
        hoursPerSession = profile.hoursPerSession
        sportsHistory = profile.sportsHistory
        currentOtherSports = profile.currentOtherSports
        weightGoal = profile.weightGoal
        strictnessLevel = profile.strictnessLevel
        migrateAndLoadAvailableDays(profile)
        availabilityDays = (0..<7).map { profile.availableDays.contains($0) }

        switch profile.trainingStyle {
        case .bodybuilding: trainingStyleKind = .bodybuilding
        case .marathon: trainingStyleKind = .marathon
        case .hybrid: trainingStyleKind = .hybrid
        case .specificSport(let sport):
            trainingStyleKind = .specificSport
            specificSport = sport
        }
    }

    private func buildTrainingStyle() -> TrainingStyle {
        switch trainingStyleKind {
        case .bodybuilding: return .bodybuilding
        case .marathon: return .marathon
        case .hybrid: return .hybrid
        case .specificSport: return .specificSport(specificSport)
        }
    }

    private func migrateAndLoadAvailableDays(_ profile: UserProfile) {
        if profile.availableDaysString.isEmpty || profile.availableDaysString == "{}" {
            if profile.availabilityJSON.count >= 7,
               profile.availabilityJSON.allSatisfy({ $0 == "1" || $0 == "0" }) {
                let indices = (0..<7).filter { i in
                    profile.availabilityJSON[profile.availabilityJSON.index(profile.availabilityJSON.startIndex, offsetBy: i)] == "1"
                }
                profile.availableDays = indices
                try? context.save()
            }
        }
    }

    private func saveProfile() {
        let trainingStyle = buildTrainingStyle()

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
        profile.trainingStyle = trainingStyle
        profile.injuryHistory = injuryHistory
        profile.injurySensitivity = injurySensitivity
        profile.sessionsPerWeek = sessionsPerWeek
        profile.hoursPerSession = hoursPerSession
        profile.sportsHistory = sportsHistory
        profile.currentOtherSports = currentOtherSports
        profile.weightGoal = weightGoal
        profile.strictnessLevel = strictnessLevel
        profile.availableDays = (0..<7).filter { availabilityDays[$0] }

        do {
            try context.save()
            saveMessage = "Profil enregistré."
        } catch {
            saveMessage = "Erreur lors de l'enregistrement."
        }
    }
}
