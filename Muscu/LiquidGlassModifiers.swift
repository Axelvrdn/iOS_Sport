//
//  LiquidGlassModifiers.swift
//  Muscu
//
//  Rôle : Modificateurs visuels Liquid Glass (barre d'onglets, cartes verre dépoli).
//  Utilisé par : ContentView (CustomFloatingTabBar), PlanningView, WorkoutView (dashboardCard).
//

import SwiftUI

// MARK: - Barre de navigation flottante (verre dépoli)

struct LiquidGlassTabBarBackground: ViewModifier {
    var cornerRadius: CGFloat = 28

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.35),
                            Color.white.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .clipShape(Capsule())
            }
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.6),
                                Color.white.opacity(0.15)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}

extension View {
    func liquidGlassTabBar(cornerRadius: CGFloat = 28) -> some View {
        modifier(LiquidGlassTabBarBackground(cornerRadius: cornerRadius))
    }
}

// MARK: - Cartes dashboard (verre léger, flottant)

struct LiquidGlassCardBackground: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                    Color.white.opacity(0.25)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        Color.white.opacity(0.4),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
            .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

extension View {
    func liquidGlassCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(LiquidGlassCardBackground(cornerRadius: cornerRadius))
    }

    /// Alias pour les vues qui utilisaient le style carte dashboard (ex. StreakDetailView, ProfileView).
    func dashboardCard(cornerRadius: CGFloat = 18) -> some View {
        liquidGlassCard(cornerRadius: cornerRadius)
    }
}
