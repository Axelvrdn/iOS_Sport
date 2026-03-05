//
//  OnboardingContainerView.swift
//  Muscu
//
//  Rôle : Point d’entrée onboarding vs app. Affiche le flux onboarding au premier lancement, puis RootView.
//  Utilisé par : MuscuApp.
//

import SwiftUI
import SwiftData
import Observation

// MARK: - Clé AppStorage

private let hasCompletedOnboardingKey = "hasCompletedOnboarding"

private extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch h.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

private struct WelcomeView: View {
    var state: OnboardingState
    @AppStorage("accentColorHex") private var accentColorHex: String = "#D0FD3E"
    @State private var glowOpacity: Double = 0.35

    private var accentColor: Color {
        Color(hex: accentColorHex.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
    }

    var body: some View {
        ZStack {
            Color(hex: "0F1115")
                .ignoresSafeArea()
            VStack(spacing: 48) {
                Spacer()
                Image("DiamondLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 160, maxHeight: 160)
                    .shadow(color: accentColor.opacity(glowOpacity), radius: 28, y: 4)
                Text("INITIALISATION DU PROTOCOLE DE PERFORMANCE...")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
                Button {
                    state.nextStep()
                } label: {
                    Text("Commencer")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "0F1115"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: accentColor.opacity(0.7), radius: 16, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                glowOpacity = 0.65
            }
        }
    }
}

// MARK: - Conteneur principal

struct OnboardingContainerView: View {
    @AppStorage(hasCompletedOnboardingKey) private var hasCompletedOnboarding = false
    @Environment(\.modelContext) private var modelContext
    @State private var onboardingState = OnboardingState()

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                RootView()
                    .onAppear {
                        Task {
                            await DataController.createDefaultProgram(context: modelContext)
                        }
                    }
            } else {
                onboardingFlow
            }
        }
        .animation(.easeInOut(duration: 0.5), value: hasCompletedOnboarding)
    }

    private var onboardingFlow: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.secondarySystemBackground).opacity(0.6)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                if onboardingState.currentStep > 0 {
                    OnboardingProgressBar(step: onboardingState.currentStep, totalSteps: OnboardingState.totalSteps - 1)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                }

                TabView(selection: $onboardingState.currentStep) {
                    WelcomeView(state: onboardingState)
                        .tag(0)
                    OnboardingStep1View(state: onboardingState)
                        .tag(1)
                    OnboardingStep2View(state: onboardingState)
                        .tag(2)
                    OnboardingStep3View(state: onboardingState)
                        .tag(3)
                    OnboardingStep4View(state: onboardingState)
                        .tag(4)
                    OnboardingFinalView(state: onboardingState, hasCompletedOnboarding: $hasCompletedOnboarding)
                        .tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.35), value: onboardingState.currentStep)
            }
        }
    }
}

// MARK: - Barre de progression

struct OnboardingProgressBar: View {
    let step: Int
    let totalSteps: Int

    private var progress: CGFloat {
        guard totalSteps > 0 else { return 0 }
        return CGFloat(step) / CGFloat(totalSteps)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: 6)

                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geo.size.width * progress), height: 6)
                    .animation(.easeInOut(duration: 0.3), value: step)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - État partagé onboarding

@Observable
final class OnboardingState {
    static let totalSteps = 6

    var currentStep: Int = 0

    // Étape 1 – Bases & objectifs
    var age: Int = 25
    var currentWeight: Double = 70
    var targetWeight: Double = 72
    var physiqueGoal: PhysiqueGoal = .maintain

    // Étape 2 – Style d’entraînement
    var trainingStyleKind: TrainingStyleKind = .bodybuilding
    var sessionsPerWeek: Int = 3
    var minutesPerSession: Int = 60
    var selectedDays: Set<Int> = [0, 2, 4] // L, M, V par défaut

    // Étape 3 – Historique & contexte
    var sportsHistoryLevel: SportsHistoryLevel = .intermediate
    var concurrentSport: String = ""
    var injurySusceptibility: InjurySensitivity = .medium

    // Étape 4 – Zones blessées
    var injuredZones: Set<String> = []

    func nextStep() {
        guard currentStep < Self.totalSteps else { return }
        currentStep += 1
    }

    func previousStep() {
        guard currentStep > 1 else { return }
        currentStep -= 1
    }

    func toggleInjuredZone(_ zoneId: String) {
        if injuredZones.contains(zoneId) {
            injuredZones.remove(zoneId)
        } else {
            injuredZones.insert(zoneId)
        }
    }
}

// TrainingStyleKind est défini dans ProfileView (bodybuilding, marathon, hybrid, specificSport).
