//
//  OnboardingStep3View.swift
//  Muscu
//
//  Vue 3 : Historique & contexte (niveau sportif, sport en parallèle, sensibilité blessures).
//

import SwiftUI

struct OnboardingStep3View: View {
    @Bindable var state: OnboardingState

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                historyLevelSection
                concurrentSportSection
                injurySusceptibilitySection
                navigationButtons
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Ton parcours sportif")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text("Contexte pour adapter les recommandations")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 4)
    }

    private var historyLevelSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Niveau d’expérience")
                .font(.headline)
            VStack(spacing: 10) {
                ForEach(SportsHistoryLevel.allCases, id: \.self) { level in
                    historyLevelRow(level)
                }
            }
        }
    }

    private func historyLevelRow(_ level: SportsHistoryLevel) -> some View {
        let isSelected = state.sportsHistoryLevel == level
        return Button {
            withAnimation(.spring(response: 0.35)) {
                state.sportsHistoryLevel = level
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: iconForHistory(level))
                    .font(.title2)
                    .foregroundStyle(isSelected ? .white : .accentColor)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(isSelected ? Color.accentColor.opacity(0.3) : Color(.tertiarySystemFill)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayNameForHistory(level))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitleForHistory(level))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func iconForHistory(_ level: SportsHistoryLevel) -> String {
        switch level {
        case .beginner: return "figure.walk"
        case .intermediate: return "figure.strengthtraining.traditional"
        case .advanced: return "flame.fill"
        }
    }

    private func displayNameForHistory(_ level: SportsHistoryLevel) -> String {
        switch level {
        case .beginner: return "Débutant"
        case .intermediate: return "Intermédiaire"
        case .advanced: return "Avancé"
        }
    }

    private func subtitleForHistory(_ level: SportsHistoryLevel) -> String {
        switch level {
        case .beginner: return "Peu ou pas d’expérience en salle"
        case .intermediate: return "Régulier depuis au moins 1 an"
        case .advanced: return "Pratique intensive, objectifs performance"
        }
    }

    private var concurrentSportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sport en parallèle (optionnel)")
                .font(.headline)
            TextField("Ex: course, natation, foot…", text: $state.concurrentSport)
                .textFieldStyle(.plain)
                .font(.body)
                .padding(14)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var injurySusceptibilitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sensibilité aux blessures")
                .font(.headline)
            HStack {
                Text("Faible")
                    .font(.caption)
                    .foregroundStyle(.green)
                Spacer()
                Text(injuryLabel)
                    .font(.subheadline.bold())
                    .foregroundStyle(injuryColor)
                Spacer()
                Text("Élevée")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Slider(
                value: Binding(
                    get: { injurySliderValue },
                    set: { state.injurySusceptibility = injuryFromSlider($0) }
                ),
                in: 0...2,
                step: 1
            )
            .tint(
                LinearGradient(
                    colors: [.green, .yellow, .red],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        .padding(20)
        .liquidGlassCard(cornerRadius: 20)
    }

    private var injurySliderValue: Double {
        switch state.injurySusceptibility {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    private func injuryFromSlider(_ value: Double) -> InjurySensitivity {
        switch value {
        case ..<0.5: return .low
        case 0.5..<1.5: return .medium
        default: return .high
        }
    }

    private var injuryLabel: String {
        switch state.injurySusceptibility {
        case .low: return "Faible"
        case .medium: return "Moyenne"
        case .high: return "Élevée"
        }
    }

    private var injuryColor: Color {
        switch state.injurySusceptibility {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            Button {
                state.previousStep()
            } label: {
                HStack {
                    Image(systemName: "arrow.left")
                    Text("Retour")
                }
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(.secondarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            Button {
                state.nextStep()
            } label: {
                HStack {
                    Text("Continuer")
                    Image(systemName: "arrow.right")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}
