//
//  OnboardingStep2View.swift
//  Muscu
//
//  Vue 2 : Style d’entraînement (grille style, fréquence, durée, jours).
//

import SwiftUI

struct OnboardingStep2View: View {
    @Bindable var state: OnboardingState

    private let dayLabels = ["L", "M", "M", "J", "V", "S", "D"]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                styleGrid
                frequencySection
                daysSection
                navigationButtons
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Ta méthode")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text("Comment tu t’entraînes au quotidien")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 4)
    }

    private var styleGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Style d’entraînement")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(TrainingStyleKind.allCases), id: \.rawValue) { kind in
                    styleCard(kind)
                }
            }
        }
    }

    private func styleCard(_ kind: TrainingStyleKind) -> some View {
        let isSelected = state.trainingStyleKind == kind
        return Button {
            withAnimation(.spring(response: 0.35)) {
                state.trainingStyleKind = kind
            }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: kind.iconName)
                    .font(.system(size: 26))
                    .foregroundStyle(isSelected ? .white : .accentColor)
                Text(kind.displayName)
                    .font(.caption.bold())
                    .foregroundStyle(isSelected ? .white : .primary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected
                          ? LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                          : LinearGradient(colors: [Color(.secondarySystemFill)], startPoint: .top, endPoint: .bottom)))
        }
        .buttonStyle(.plain)
    }

    private var frequencySection: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Séances par semaine")
                    .font(.headline)
                Spacer()
                Stepper("\(state.sessionsPerWeek)", value: $state.sessionsPerWeek, in: 1...7)
                    .labelsHidden()
                Text("\(state.sessionsPerWeek)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .frame(width: 28, alignment: .trailing)
            }
            Divider()
            HStack {
                Text("Durée par séance (min)")
                    .font(.headline)
                Spacer()
                Stepper("\(state.minutesPerSession)", value: $state.minutesPerSession, in: 15...180, step: 15)
                    .labelsHidden()
                Text("\(state.minutesPerSession)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(20)
        .liquidGlassCard(cornerRadius: 20)
    }

    private var daysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jours disponibles")
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { index in
                    dayChip(index)
                }
            }
        }
    }

    private func dayChip(_ index: Int) -> some View {
        let isSelected = state.selectedDays.contains(index)
        let label = dayLabels[index]
        return Button {
            if state.selectedDays.contains(index) {
                state.selectedDays.remove(index)
            } else {
                state.selectedDays.insert(index)
            }
        } label: {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(isSelected ? Color.accentColor : Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
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
