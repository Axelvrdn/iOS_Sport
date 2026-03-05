//
//  OnboardingFinalView.swift
//  Muscu
//
//  Dernière étape : bouton « Terminer mon profil », sauvegarde SwiftData et passage à l’app.
//

import SwiftUI
import SwiftData

struct OnboardingFinalView: View {
    var state: OnboardingState
    @Binding var hasCompletedOnboarding: Bool
    @Environment(\.modelContext) private var modelContext

    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                summaryCard
                finishButton
                if let msg = errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 40)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
            Text("Ton profil est prêt")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text("On enregistre tes préférences pour personnaliser ton expérience.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Récapitulatif")
                .font(.headline)
            summaryRow("Objectif", state.physiqueGoal.displayName)
            summaryRow("Style", state.trainingStyleKind.displayName)
            summaryRow("Séances / semaine", "\(state.sessionsPerWeek)")
            summaryRow("Durée", "\(state.minutesPerSession) min")
            summaryRow("Niveau", sportsHistoryDisplay)
            if !state.injuredZones.isEmpty {
                summaryRow("Zones sensibles", "\(state.injuredZones.count)")
            }
        }
        .padding(20)
        .liquidGlassCard(cornerRadius: 20)
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }

    private var sportsHistoryDisplay: String {
        switch state.sportsHistoryLevel {
        case .beginner: return "Débutant"
        case .intermediate: return "Intermédiaire"
        case .advanced: return "Avancé"
        }
    }

    private var finishButton: some View {
        Button {
            saveAndFinish()
        } label: {
            HStack(spacing: 10) {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Terminer mon profil")
                        .font(.headline)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(isSaving)
    }

    private func saveAndFinish() {
        errorMessage = nil
        isSaving = true

        let profile: UserProfile
        let fetch = FetchDescriptor<UserProfile>()
        let existing = (try? modelContext.fetch(fetch)) ?? []

        if let first = existing.first {
            profile = first
        } else {
            profile = UserProfile()
            modelContext.insert(profile)
        }

        profile.age = state.age
        profile.weight = state.currentWeight
        profile.weightGoal = state.targetWeight
        profile.physiqueGoal = state.physiqueGoal
        profile.trainingStyle = state.trainingStyleKind.toTrainingStyle(specificSport: .volley)
        profile.sessionsPerWeek = state.sessionsPerWeek
        profile.hoursPerSession = Double(state.minutesPerSession) / 60.0
        profile.availableDays = state.selectedDays.sorted()
        profile.sportsHistory = state.sportsHistoryLevel.rawValue
        profile.currentOtherSports = state.concurrentSport
        profile.injurySensitivity = state.injurySusceptibility
        profile.injuredZones = Array(state.injuredZones)

        do {
            try modelContext.save()
            withAnimation(.easeInOut(duration: 0.5)) {
                hasCompletedOnboarding = true
            }
        } catch {
            errorMessage = "Erreur : \(error.localizedDescription)"
        }
        isSaving = false
    }
}
