import SwiftUI

/// Onboarding principal : sélection des disciplines + environnement + CTA "Générer mon plan".
struct IntroView: View {
    @Bindable var state: OnboardingState
    @State private var warningText: String?
    @State private var currentDisciplineIndex: Int = 0

    private let gridColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    private let dayOrder: [(day: DayOfWeek, short: String, label: String)] = [
        (.monday, "L", "Lundi"),
        (.tuesday, "M", "Mardi"),
        (.wednesday, "M", "Mercredi"),
        (.thursday, "J", "Jeudi"),
        (.friday, "V", "Vendredi"),
        (.saturday, "S", "Samedi"),
        (.sunday, "D", "Dimanche")
    ]

    private var sortedDisciplines: [Discipline] {
        state.selectedDisciplines.sorted { $0.displayName < $1.displayName }
    }

    private var planningIsComplete: Bool {
        let discs = sortedDisciplines
        guard !discs.isEmpty else { return false }
        return discs.allSatisfy { d in
            guard let days = state.disciplineSchedule[d] else { return false }
            return !days.isEmpty
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.06, green: 0.07, blue: 0.10)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                header
                disciplinesGrid
                environmentSegment
                planningSection
                if let warning = warningText {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Spacer()
                if planningIsComplete {
                    generateButton
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 32)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Ton profil d'athlète hybride")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Choisis jusqu'à 3 disciplines, ton environnement, puis planifie tes jours par pratique.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
    }

    private var disciplinesGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Disciplines")
                .font(.headline)
                .foregroundStyle(.white)

            LazyVGrid(columns: gridColumns, spacing: 14) {
                ForEach(Discipline.allCases) { d in
                    disciplineCard(for: d)
                }
            }
        }
    }

    private func disciplineCard(for discipline: Discipline) -> some View {
        let isSelected = state.selectedDisciplines.contains(discipline)

        return Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                toggleDiscipline(discipline)
            }
        } label: {
            VStack(spacing: 10) {
                Text("\(discipline.emoji) \(discipline.displayName)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.12 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.white.opacity(0.18),
                        lineWidth: isSelected ? 2 : 0.8
                    )
                    .shadow(color: isSelected ? Color.accentColor.opacity(0.6) : .clear,
                            radius: isSelected ? 10 : 0,
                            x: 0,
                            y: isSelected ? 4 : 0)
            )
        }
        .buttonStyle(.plain)
    }

    private func toggleDiscipline(_ d: Discipline) {
        if state.selectedDisciplines.contains(d) {
            state.selectedDisciplines.remove(d)
            warningText = nil
            // Nettoie le planning associé si on supprime une discipline.
            state.disciplineSchedule[d] = nil
        } else if state.selectedDisciplines.count < 3 {
            state.selectedDisciplines.insert(d)
            warningText = nil
        } else {
            warningText = "Le focus est la clé de la performance. Choisis tes 3 priorités."
        }
        // Recalibre l’index courant si nécessaire.
        currentDisciplineIndex = min(currentDisciplineIndex, max(0, sortedDisciplines.count - 1))
    }

    private var environmentSegment: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Setup de l'Architecte")
                .font(.headline)
                .foregroundStyle(.white)
            HStack(spacing: 12) {
                envTile(kind: .noGym,
                        title: "🏠 Maison / Poids du corps",
                        subtitle: "Parcs, maison, extérieur.\nProfil No‑Gym.")
                envTile(kind: .gym,
                        title: "🏢 Salle de Sport",
                        subtitle: "Machines, barres, charges.\nProfil Gym Edition.")
            }
        }
    }

    // MARK: - Planning par discipline

    private var planningSection: some View {
        let discs = sortedDisciplines
        guard !discs.isEmpty else { return AnyView(EmptyView()) }

        let currentIndex = min(currentDisciplineIndex, max(0, discs.count - 1))
        let currentDiscipline = discs[currentIndex]

        // Jours déjà occupés par les autres disciplines (anti‑doublon).
        let occupiedByOthers: Set<DayOfWeek> = state.disciplineSchedule
            .filter { key, _ in key != currentDiscipline }
            .values
            .reduce(into: Set<DayOfWeek>()) { acc, set in acc.formUnion(set) }

        return AnyView(
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Quand pratiques-tu : \(currentDiscipline.emoji) \(currentDiscipline.displayName) ?")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                }

                HStack(spacing: 8) {
                    ForEach(dayOrder, id: \.day) { info in
                        dayButton(for: info.day,
                                  short: info.short,
                                  label: info.label,
                                  discipline: currentDiscipline,
                                  occupiedByOthers: occupiedByOthers)
                    }
                }

                if discs.count > 1 {
                    HStack {
                        Text("Discipline \(currentIndex + 1) sur \(discs.count)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                currentDisciplineIndex = max(0, currentDisciplineIndex - 1)
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .foregroundStyle(.white.opacity(currentIndex > 0 ? 1 : 0.3))
                        .disabled(currentIndex == 0)

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                currentDisciplineIndex = min(discs.count - 1, currentDisciplineIndex + 1)
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .foregroundStyle(.white.opacity(currentIndex < discs.count - 1 ? 1 : 0.3))
                        .disabled(currentIndex >= discs.count - 1)
                    }
                }
            }
        )
    }

    private func dayButton(
        for day: DayOfWeek,
        short: String,
        label: String,
        discipline: Discipline,
        occupiedByOthers: Set<DayOfWeek>
    ) -> some View {
        let isDisabled = occupiedByOthers.contains(day)
        let selectedSet = state.disciplineSchedule[discipline] ?? []
        let isSelected = selectedSet.contains(day)

        return Button {
            guard !isDisabled else { return }
            var updated = selectedSet
            if updated.contains(day) {
                updated.remove(day)
            } else {
                updated.insert(day)
            }
            state.disciplineSchedule[discipline] = updated
        } label: {
            VStack(spacing: 4) {
                Text(short)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Circle()
                    .fill(isDisabled ? Color.white.opacity(0.1) : (isSelected ? Color.accentColor : Color.clear))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isDisabled ? Color.white.opacity(0.15) :
                                    (isSelected ? Color.accentColor : Color.white.opacity(0.4)),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            }
            .foregroundStyle(isDisabled ? Color.white.opacity(0.25) : Color.white)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(Text(label))
    }

    private func envTile(kind: EnvironmentKind, title: String, subtitle: String) -> some View {
        let isSelected = state.environmentKind == kind
        return Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                state.environmentKind = kind
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(3)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.16 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.white.opacity(0.18),
                                  lineWidth: isSelected ? 1.6 : 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private var generateButton: some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                state.nextStep()
            }
        } label: {
            HStack {
                Text("Finaliser la planification")
                Image(systemName: "arrow.right.circle.fill")
            }
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(planningIsComplete ? Color.accentColor : Color.gray)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: state.selectedDisciplines.isEmpty ? .clear : Color.accentColor.opacity(0.6),
                    radius: 16, y: 6)
        }
        .disabled(!planningIsComplete)
    }
}

