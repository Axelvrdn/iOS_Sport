//
//  MuscuApp.swift
//  Muscu
//
//  Rôle : Point d’entrée de l’app ; configure le ModelContainer SwiftData et affiche le splash puis ContentView.
//  Utilisé par : Aucun (racine).
//

import SwiftUI
import SwiftData

@main
struct MuscuApp: App {
    var body: some Scene {
        WindowGroup {
            OnboardingContainerView()
        }
        .modelContainer(for: [
            UserProfile.self,
            WorkoutProgram.self,
            Exercise.self,
            DailyLog.self,
            WorkoutHistorySession.self,
            WorkoutLog.self,
            ExerciseSetResult.self,
            TrainingProgram.self,
            TrainingWeek.self,
            TrainingDay.self,
            WorkoutSession.self,
            ExerciseMaster.self,
            SessionExercise.self,
            SessionRecipe.self
        ])
        // Tous les @Model de Models.swift sont listés ci‑dessus. Ne pas ajouter de MigrationPlan
        // ni modifier les deleteRule sans coordination (risque de corruptions).
    }
}

/// Vue racine : splash (Diamond) puis contenu principal. Visible par OnboardingContainerView.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showMainApp: Bool = false

    var body: some View {
        Group {
            if showMainApp {
                ContentView()
                    .onAppear {
                        // Seeding au premier affichage du contenu principal (après le splash).
                        Task {
                            await DataController.createDefaultProgram(context: modelContext)
                        }
                    }
            } else {
                LaunchScreenView()
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    showMainApp = true
                }
            }
        }
    }
}
