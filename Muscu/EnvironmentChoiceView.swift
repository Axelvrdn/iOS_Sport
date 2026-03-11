import SwiftUI

private extension Color {
    init(hexString: String) {
        let h = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch h.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

/// Écran 3 : Environnement — choix Gym / No‑Gym.
struct EnvironmentChoiceView: View {
    @Bindable var state: OnboardingState
    @AppStorage("accentColorHex") private var accentColorHex: String = "#D0FD3E"
    @State private var selection: EnvironmentKind? = nil

    private var accentColor: Color {
        Color(hexString: accentColorHex.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                environmentOptions
                nextButton
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .onAppear {
            selection = state.environmentKind
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Où s'entraîne l'architecte ?")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text("Choisis ton environnement principal. Tu pourras toujours mixer par la suite.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var environmentOptions: some View {
        VStack(spacing: 16) {
            environmentCard(kind: .gym,
                            title: "Accès Salle de Sport",
                            subtitle: "Machines, barres, charges lourdes.\nVersion Gym Edition du programme.",
                            icon: "dumbbell.fill")
            environmentCard(kind: .noGym,
                            title: "Poids du Corps / Extérieur",
                            subtitle: "Parcs, rue, terrain.\nVersion No‑Gym optimisée pour la liberté.",
                            icon: "figure.walk")
        }
    }

    private func environmentCard(kind: EnvironmentKind,
                                 title: String,
                                 subtitle: String,
                                 icon: String) -> some View {
        let isSelected = selection == kind
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selection = kind
                state.environmentKind = kind
            }
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isSelected ? accentColor : Color(.tertiarySystemFill))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.black : accentColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(accentColor)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isSelected ? accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var nextButton: some View {
        Button {
            guard selection != nil else { return }
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
            .background(selection == nil ? Color.gray : accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .disabled(selection == nil)
    }
}

enum EnvironmentKind: String, Codable {
    case gym
    case noGym
}

extension OnboardingState {
    var environmentKind: EnvironmentKind {
        get { _environmentKind ?? .gym }
        set { _environmentKind = newValue }
    }

    // stock interne optionnel (pour compat), sérialisé via OnboardingState si besoin
    fileprivate var _environmentKind: EnvironmentKind? {
        get { _environmentKindStorage }
        set { _environmentKindStorage = newValue }
    }
}

// Stockage local simple (non persisté en SwiftData, juste en mémoire onboarding)
fileprivate var _environmentKindStorage: EnvironmentKind? = nil

