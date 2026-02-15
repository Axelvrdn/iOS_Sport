//
//  MuscuApp.swift
//  Muscu
//
//  Created by Axel Verdon on 27/01/2026.
//

import SwiftUI
import SwiftData

@main
struct MuscuApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [
            UserProfile.self,
            WorkoutProgram.self,
            Exercise.self,
            DailyLog.self,
            WorkoutHistorySession.self,
            WorkoutLog.self,
            TrainingProgram.self,
            TrainingWeek.self,
            TrainingDay.self,
            WorkoutSession.self,
            ExerciseMaster.self,
            SessionExercise.self,
            SessionRecipe.self
        ])
    }
}

/// Vue racine : splash (Diamond) puis contenu principal.
private struct RootView: View {
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
