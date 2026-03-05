//
//  OnboardingStep4View.swift
//  Muscu
//
//  Vue 4 : Carte des zones sensibles (SceneKit 3D, tap pour marquer/démarquer).
//

import SwiftUI

struct OnboardingStep4View: View {
    var state: OnboardingState

    var body: some View {
        VStack(spacing: 0) {
            header
            bodyMapArea
            legendAndNav
        }
        .padding(.bottom, 24)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Zones sensibles")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text("Touche une zone pour la marquer comme sensible ou blessée. Re-touche pour annuler.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var bodyMapArea: some View {
        BodyMapSceneKitView(
            selectedZoneIds: state.injuredZones,
            onZoneTapped: { zoneId in
                state.toggleInjuredZone(zoneId)
            }
        )
        .frame(height: 380)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var legendAndNav: some View {
        VStack(spacing: 16) {
            if !state.injuredZones.isEmpty {
                Text("\(state.injuredZones.count) zone(s) sélectionnée(s)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }
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
            .padding(.horizontal, 24)
        }
        .padding(.top, 12)
    }
}
