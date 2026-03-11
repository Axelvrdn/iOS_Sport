import SwiftUI

/// Onboarding principal : sélection des disciplines + environnement + CTA "Générer mon plan".
struct IntroView: View {
    @Bindable var state: OnboardingState
    @State private var warningText: String?

    private let gridColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

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
                if let warning = warningText {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Spacer()
                generateButton
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
            Text("Choisis jusqu'à 3 disciplines. Le coach adaptera automatiquement les programmes, la fatigue et les semaines de deload.")
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
        let emoji = discipline.emoji
        let title = discipline.displayName

        return Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                toggleDiscipline(discipline)
            }
        } label: {
            VStack(spacing: 10) {
                Text(emoji)
                    .font(.system(size: 26))
                Text(title)
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
        } else if state.selectedDisciplines.count < 3 {
            state.selectedDisciplines.insert(d)
            warningText = nil
        } else {
            warningText = "Le focus est la clé de la performance. Choisis tes 3 priorités."
        }
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
                Text("Générer mon plan")
                Image(systemName: "arrow.right.circle.fill")
            }
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(state.selectedDisciplines.isEmpty ? Color.gray : Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: state.selectedDisciplines.isEmpty ? .clear : Color.accentColor.opacity(0.6),
                    radius: 16, y: 6)
        }
        .disabled(state.selectedDisciplines.isEmpty)
    }
}

