//
//  SessionRunnerView.swift
//  Muscu
//
//  Vue immersive pour exécuter une séance en temps réel.
//

import SwiftUI
import SwiftData
import AVFoundation
import UIKit

enum RunnerState {
    case overview
    case exerciseActive
    case restTimer
    case summary
}

struct SessionRunnerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let program: WorkoutProgram?
    let exercises: [Exercise]
    let phaseIndex: Int
    let dayIndex: Int

    @State private var state: RunnerState = .overview
    @State private var currentExerciseIndex: Int = 0
    @State private var currentSetIndex: Int = 1
    @State private var totalSetsForExercise: Int = 3

    @State private var targetReps: String = ""
    @State private var targetWeight: String = ""
    @State private var actualReps: String = ""
    @State private var actualWeight: String = ""

    @State private var restRemaining: Int = 0
    @State private var restTimer: Timer?
    @State private var startDate: Date = .now

    var body: some View {
        VStack {
            switch state {
            case .overview:
                overviewView
            case .exerciseActive:
                exerciseActiveView
            case .restTimer:
                restTimerView
            case .summary:
                summaryView
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            startDate = .now
            prepareFirstExercise()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            restTimer?.invalidate()
        }
        .navigationBarBackButtonHidden(state != .summary)
    }

    // MARK: - Subviews

    private var overviewView: some View {
        VStack(spacing: 24) {
            Text(program?.name ?? "Séance")
                .font(.title.bold())
            Text("Jour \(dayIndex) • \(exercises.count) exercices")
                .foregroundStyle(.secondary)

            Button("Démarrer") {
                state = .exerciseActive
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
    }

    private var exerciseActiveView: some View {
        let exercise = exercises[currentExerciseIndex]

        return VStack(spacing: 16) {
            Text("Exercice \(currentExerciseIndex + 1)/\(exercises.count)")
                .font(.headline)

            Text(exercise.name)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)

            Text(exercise.setsRepsDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let urlString = exercise.videoUrl,
               let url = URL(string: urlString) {
                Button("Voir la vidéo") {
                    openURL(url)
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Série \(currentSetIndex)")
                    .font(.headline)

                TextField("Reps cibles", text: $targetReps)
                    .textFieldStyle(.roundedBorder)
                TextField("Charge cible (kg)", text: $targetWeight)
                    .textFieldStyle(.roundedBorder)

                TextField("Reps réalisées", text: $actualReps)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                TextField("Charge utilisée (kg)", text: $actualWeight)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.vertical)

            Button("Valider la série") {
                validateSet(for: exercise)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)

            Spacer()
        }
        .padding()
    }

    private var restTimerView: some View {
        VStack(spacing: 24) {
            Text("Repos")
                .font(.title.bold())

            Text("\(restRemaining) s")
                .font(.system(size: 48, weight: .bold, design: .rounded))

            HStack(spacing: 16) {
                Button("-10s") {
                    restRemaining = max(0, restRemaining - 10)
                }
                .buttonStyle(.bordered)

                Button("+10s") {
                    restRemaining += 10
                }
                .buttonStyle(.bordered)

                Button("Skip") {
                    finishRest()
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding()
    }

    private var summaryView: some View {
        VStack(spacing: 24) {
            Text("Séance terminée")
                .font(.title.bold())

            Text("Bravo !")
                .font(.headline)

            Button("Terminer") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
    }

    // MARK: - Logic

    private func prepareFirstExercise() {
        guard !exercises.isEmpty else { return }
        currentExerciseIndex = 0
        currentSetIndex = 1
        extractTargetInfo(from: exercises[0])
    }

    private func extractTargetInfo(from exercise: Exercise) {
        targetReps = exercise.setsRepsDescription
        targetWeight = ""
    }

    private func validateSet(for exercise: Exercise) {
        let reps = Int(actualReps) ?? 0
        let weight = Double(actualWeight.replacingOccurrences(of: ",", with: ".")) ?? 0

        let log = WorkoutLog(
            programName: program?.name ?? "",
            phaseIndex: phaseIndex,
            dayIndex: dayIndex,
            exerciseName: exercise.name,
            setIndex: currentSetIndex,
            targetReps: targetReps,
            actualReps: reps,
            actualWeight: weight
        )
        context.insert(log)
        try? context.save()

        startRest(for: exercise)
    }

    private func startRest(for exercise: Exercise) {
        restTimer?.invalidate()
        restRemaining = exercise.restSeconds
        state = .restTimer

        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if restRemaining > 0 {
                restRemaining -= 1
            } else {
                restTimer?.invalidate()
                playEndSound()
                finishRest()
            }
        }
    }

    private func finishRest() {
        if currentSetIndex < totalSetsForExercise {
            currentSetIndex += 1
            actualReps = ""
            actualWeight = ""
            state = .exerciseActive
        } else if currentExerciseIndex + 1 < exercises.count {
            currentExerciseIndex += 1
            currentSetIndex = 1
            actualReps = ""
            actualWeight = ""
            extractTargetInfo(from: exercises[currentExerciseIndex])
            state = .exerciseActive
        } else {
            completeSession()
        }
    }

    private func completeSession() {
        if let program {
            let totalDuration = Int(Date().timeIntervalSince(startDate))
            let session = WorkoutHistorySession(
                date: .now,
                programName: program.name,
                phaseIndex: phaseIndex,
                dayIndex: dayIndex,
                completionPercentage: 100,
                averageRestTimeSeconds: 60,
                totalDurationSeconds: totalDuration,
                isCompleted: true,
                isSkipped: false
            )
            session.program = program
            context.insert(session)
            try? context.save()
        }
        state = .summary
    }

    private func playEndSound() {
        AudioServicesPlaySystemSound(1005)
    }
}

