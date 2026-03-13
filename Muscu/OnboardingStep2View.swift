//
//  OnboardingStep2View.swift
//  Muscu
//
//  Vue 2 : Style d’entraînement (grille style, fréquence, durée, jours).
//

import SwiftUI

struct OnboardingStep2View: View {
    @Bindable var state: OnboardingState

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                styleGrid
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
