//
//  OnboardingStep1View.swift
//  Muscu
//
//  Vue 1 : Les bases & objectifs (âge, poids, objectif physique).
//

import SwiftUI

struct OnboardingStep1View: View {
    @Bindable var state: OnboardingState

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                ageSection
                weightSection
                physiqueGoalSection
                nextButton
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Faisons connaissance")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text("Quelques infos pour personnaliser ton expérience")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)
    }

    private var ageSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Âge")
                    .font(.headline)
                Spacer()
                Text("\(state.age) ans")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
            }
            Slider(value: Binding(
                get: { Double(state.age) },
                set: { state.age = Int($0.rounded()) }
            ), in: 14...80, step: 1)
            .tint(.accentColor)
        }
        .padding(20)
        .liquidGlassCard(cornerRadius: 20)
    }

    private var weightSection: some View {
        VStack(spacing: 20) {
            weightRow(label: "Poids actuel", value: $state.currentWeight, unit: "kg")
            weightRow(label: "Poids cible", value: $state.targetWeight, unit: "kg")
        }
        .padding(20)
        .liquidGlassCard(cornerRadius: 20)
    }

    private func weightRow(label: String, value: Binding<Double>, unit: String) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(label)
                    .font(.headline)
                Spacer()
                Text("\(value.wrappedValue, specifier: "%.0f") \(unit)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
            }
            Slider(value: value, in: 40...150, step: 1)
                .tint(.accentColor)
        }
    }

    private var physiqueGoalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Objectif physique")
                .font(.headline)
            HStack(spacing: 12) {
                ForEach(PhysiqueGoal.allCases, id: \.self) { goal in
                    physiqueGoalCard(goal)
                }
            }
        }
    }

    private func physiqueGoalCard(_ goal: PhysiqueGoal) -> some View {
        let isSelected = state.physiqueGoal == goal
        return Button {
            withAnimation(.spring(response: 0.35)) {
                state.physiqueGoal = goal
            }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: goal.iconName)
                    .font(.system(size: 28))
                    .foregroundStyle(isSelected ? .white : .accentColor)
                Text(goal.displayName)
                    .font(.caption.bold())
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected
                          ? LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                          : LinearGradient(colors: [Color(.secondarySystemFill)], startPoint: .top, endPoint: .bottom)))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var nextButton: some View {
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
