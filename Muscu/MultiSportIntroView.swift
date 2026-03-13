import SwiftUI

/// Écran 1 : La Promesse — Elite Architect.
struct MultiSportIntroView: View {
    @Bindable var state: OnboardingState

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.06, green: 0.07, blue: 0.09)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 10) {
                    Text("Elite Architect")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("L'intelligence artificielle locale au service de l'athlète hybride.")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .frame(height: 180)
                        .padding(.horizontal, 32)

                    VStack(spacing: 16) {
                        HStack {
                            Text("100% On‑Device AI")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color.green.opacity(0.18))
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.green.opacity(0.7), lineWidth: 1)
                                )
                            Spacer()
                        }
                        .padding(.horizontal, 40)

                        Spacer()

                        Text("Planification, deload, préhab et suivi force\nsans quitter ton appareil.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                        Spacer(minLength: 8)
                    }
                }
                .shadow(color: Color.accentColor.opacity(0.4), radius: 24, y: 6)

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        state.nextStep()
                    }
                } label: {
                    HStack {
                        Text("Configurer mon profil athlétique")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: Color.accentColor.opacity(0.7), radius: 18, y: 6)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

