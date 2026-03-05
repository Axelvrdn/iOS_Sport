//
//  SessionRunnerView.swift
//  Muscu
//
//  Écran d'entraînement actif — DA Elite Athlete : cockpit dark, chrono géant, zone média, rulers tactiles.
//

import SwiftUI
import SwiftData
import AudioToolbox
import UIKit

// MARK: - Runner Elite Design (Cockpit)

private let RunnerBackgroundDark = Color(hex: "0F1115")
private let RunnerCardDark = Color(hex: "1C1F26")

extension Notification.Name {
    static let sessionRunnerDidAppear = Notification.Name("sessionRunnerDidAppear")
    static let sessionRunnerDidDisappear = Notification.Name("sessionRunnerDidDisappear")
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

enum RunnerState {
    case overview
    case exerciseActive
    case restTimer
    case summary
}

/// Unité d'exercice pour le runner (atomique ou legacy).
struct RunnerItem {
    let exerciseName: String
    let targetReps: String
    let restSeconds: Int
    let sets: Int
    let videoUrl: String?
    let visualAsset: String
    /// Référence au master (atomique) pour 1RM et ExerciseSetResult.
    let exerciseMaster: ExerciseMaster?
}

struct SessionRunnerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Query private var profiles: [UserProfile]

    // Atomique
    let recipe: SessionRecipe?
    let programName: String
    let weekNumber: Int
    let dayIndex: Int
    // Legacy
    let program: WorkoutProgram?
    let exercises: [Exercise]
    let phaseIndex: Int
    let dayIndexLegacy: Int

    private let runnerItems: [RunnerItem]
    private let isAtomique: Bool

    init(recipe: SessionRecipe, programName: String, weekNumber: Int, dayIndex: Int) {
        self.recipe = recipe
        self.programName = programName
        self.weekNumber = weekNumber
        self.dayIndex = dayIndex
        self.program = nil
        self.exercises = []
        self.phaseIndex = 1
        self.dayIndexLegacy = dayIndex
        self.isAtomique = true
        self.runnerItems = recipe.exercises.map { se in
            RunnerItem(
                exerciseName: se.exercise?.name ?? "Exercice",
                targetReps: se.reps,
                restSeconds: se.restTime,
                sets: se.sets,
                videoUrl: se.exercise?.videoUrl,
                visualAsset: se.exercise?.visualAsset ?? "figure.strengthtraining.traditional",
                exerciseMaster: se.exercise
            )
        }
    }

    init(program: WorkoutProgram?, exercises: [Exercise], phaseIndex: Int, dayIndex: Int) {
        self.recipe = nil
        self.programName = program?.name ?? "Séance"
        self.weekNumber = 1
        self.dayIndex = dayIndex
        self.program = program
        self.exercises = exercises
        self.phaseIndex = phaseIndex
        self.dayIndexLegacy = dayIndex
        self.isAtomique = false
        self.runnerItems = exercises.map { ex in
            RunnerItem(
                exerciseName: ex.name,
                targetReps: ex.setsRepsDescription,
                restSeconds: ex.restSeconds,
                sets: 3,
                videoUrl: ex.videoUrl,
                visualAsset: "figure.strengthtraining.traditional",
                exerciseMaster: nil
            )
        }
    }

    @State private var state: RunnerState = .overview
    @State private var currentExerciseIndex: Int = 0
    @State private var currentSetIndex: Int = 1
    @State private var totalSetsForExercise: Int = 3

    @State private var executionElapsedSeconds: Int = 0
    @State private var executionTimer: Timer?
    @State private var showSetInputModal: Bool = false
    @State private var totalVolumeAccumulated: Double = 0

    @State private var restRemaining: Int = 0
    @State private var restTimer: Timer?
    @State private var restJustEnded: Bool = false
    @State private var startDate: Date = .now
    @Environment(\.accentColor) private var accentColor
    @Environment(\.textOnAccentColor) private var textOnAccentColor

    private var userProfile: UserProfile? { profiles.first }
    private var currentItem: RunnerItem? {
        guard currentExerciseIndex < runnerItems.count else { return nil }
        return runnerItems[currentExerciseIndex]
    }

    private var runnerBackground: Color {
        colorScheme == .dark ? RunnerBackgroundDark : Color.white
    }

    private var runnerChronoColor: Color {
        accentColor
    }

    private var runnerChronoGlow: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            runnerBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                switch state {
                case .overview:
                    overviewView
                case .exerciseActive:
                    exerciseActiveView
                        .id("\(currentExerciseIndex)-\(currentSetIndex)")
                        .opacity(showSetInputModal ? 0.3 : 1)
                        .blur(radius: showSetInputModal ? 4 : 0)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                case .restTimer:
                    restTimerView
                        .transition(.scale.combined(with: .opacity))
                case .summary:
                    summaryView
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .animation(.easeInOut(duration: 0.35), value: state)
        }
        .navigationBarBackButtonHidden(state != .summary)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            startDate = .now
            if !runnerItems.isEmpty {
                totalSetsForExercise = runnerItems[currentExerciseIndex].sets
            }
            NotificationCenter.default.post(name: .sessionRunnerDidAppear, object: nil)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            executionTimer?.invalidate()
            restTimer?.invalidate()
            NotificationCenter.default.post(name: .sessionRunnerDidDisappear, object: nil)
        }
        .overlay {
            if showSetInputModal {
                performanceCardOverlay
            }
        }
    }

    // MARK: - Overview

    private var overviewView: some View {
        VStack(spacing: 28) {
            Spacer().frame(height: 40)
            Text(recipe?.name ?? programName)
                .font(.title.bold())
                .foregroundStyle(Color.primary)
            Text("\(runnerItems.count) exercices")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                guard !runnerItems.isEmpty else { return }
                state = .exerciseActive
                startExecutionChrono()
            } label: {
                Text("Démarrer")
                    .font(.headline)
                    .foregroundStyle(runnerItems.isEmpty ? .gray : textOnAccentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(runnerItems.isEmpty ? Color.gray.opacity(0.5) : accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(runnerItems.isEmpty)
            .padding(.horizontal, 32)
            .padding(.top, 16)
            Spacer()
        }
    }

    // MARK: - Exercise Active

    private var exerciseActiveView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                mediaSection
                consignesSection
                chronoSectionGiant
                seriesBadgesSection
                finiButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 100)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Exercice \(currentExerciseIndex + 1)/\(runnerItems.count)")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            Text(currentItem?.exerciseName ?? "")
                .font(.title2.bold())
                .foregroundStyle(Color.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mediaSection: some View {
        Group {
            if let item = currentItem, item.videoUrl != nil, !(item.videoUrl?.isEmpty ?? true) {
                YouTubeEmbedView(videoUrl: item.videoUrl)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(accentColor, lineWidth: 1.5)
                    )
            } else {
                ZStack(alignment: .bottomLeading) {
                    Image(systemName: currentItem?.visualAsset ?? "figure.strengthtraining.traditional")
                        .font(.system(size: 80))
                        .foregroundStyle(Color.primary.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .background(RunnerCardDark.opacity(colorScheme == .dark ? 1 : 0.15))
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    Text(currentItem?.exerciseName ?? "")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(16)
                }
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(accentColor.opacity(0.6), lineWidth: 1)
                )
            }
        }
    }

    private var consignesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Objectif de la série")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Série \(currentSetIndex) : \(currentItem?.targetReps ?? "")")
                .font(.title3.bold())
                .foregroundStyle(Color.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var chronoSectionGiant: some View {
        let progress = (Double(executionElapsedSeconds % 60) / 60.0)
        return ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 148, height: 148)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(runnerChronoColor.opacity(runnerChronoGlow ? 0.6 : 0.5), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 148, height: 148)
                .animation(.linear(duration: 0.5), value: executionElapsedSeconds)
            Text(formatElapsed(executionElapsedSeconds))
                .font(.system(size: 56, weight: .bold, design: .monospaced))
                .foregroundStyle(runnerChronoColor)
                .shadow(color: runnerChronoGlow ? runnerChronoColor.opacity(0.5) : .clear, radius: 10)
                .shadow(color: !runnerChronoGlow ? Color.black.opacity(0.2) : .clear, radius: 8, x: 0, y: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var seriesBadgesSection: some View {
        HStack(spacing: 10) {
            ForEach(1...totalSetsForExercise, id: \.self) { idx in
                let isDone = idx < currentSetIndex
                let isCurrent = idx == currentSetIndex
                Text("\(idx)/\(totalSetsForExercise)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(isCurrent ? textOnAccentColor : (isDone ? runnerChronoColor : Color.secondary))
                    .frame(minWidth: 44, minHeight: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isCurrent ? accentColor : (isDone ? runnerChronoColor.opacity(0.25) : Color.primary.opacity(0.08)))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isCurrent ? accentColor : Color.clear, lineWidth: 1.5)
                    )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var finiButton: some View {
        Button {
            executionTimer?.invalidate()
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                showSetInputModal = true
            }
        } label: {
            Text("SÉRIE TERMINÉE")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(textOnAccentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(.top, 12)
    }

    // MARK: - Performance Card Overlay (glassmorphism)

    private var performanceCardOverlay: some View {
        ZStack {
            Color.black.opacity(0.01)
                .ignoresSafeArea()
            PerformanceCardView(
                setIndex: currentSetIndex,
                targetReps: currentItem?.targetReps ?? "",
                currentEstimatedOneRM: currentItem?.exerciseMaster?.estimatedOneRM ?? 0,
                onValidate: { reps, weight, isPR in
                    validateSet(reps: reps, weight: weight, isPR: isPR)
                    withAnimation(.easeOut(duration: 0.25)) {
                        showSetInputModal = false
                    }
                },
                onDismiss: {
                    withAnimation(.easeOut(duration: 0.25)) {
                        showSetInputModal = false
                    }
                    executionElapsedSeconds = 0
                    startExecutionChrono()
                }
            )
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showSetInputModal)
    }

    // MARK: - Rest Timer

    private var restTimerView: some View {
        VStack(spacing: 32) {
            Text("Repos")
                .font(.title2.bold())
                .foregroundStyle(.secondary)
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 160, height: 160)
                let totalRest = currentItem?.restSeconds ?? 60
                let progress = totalRest > 0 ? CGFloat(restRemaining) / CGFloat(totalRest) : 0
                Circle()
                    .trim(from: 0, to: 1 - progress)
                    .stroke(restRemaining <= 10 ? Color.orange : runnerChronoColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 160, height: 160)
                    .animation(.easeInOut(duration: 0.3), value: restRemaining)
                Text(formatElapsed(restRemaining))
                    .font(.system(size: 52, weight: .bold, design: .monospaced))
                    .foregroundStyle(restRemaining <= 10 ? .orange : runnerChronoColor)
                    .contentTransition(.numericText())
                    .shadow(color: runnerChronoGlow ? runnerChronoColor.opacity(0.4) : .clear, radius: 8)
            }

            if restRemaining == 0 {
                Button {
                    finishRest()
                } label: {
                    Text("Passer à la suite")
                        .font(.headline)
                        .foregroundStyle(textOnAccentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 32)
                .padding(.top, 16)
                .transition(.scale.combined(with: .opacity))
            } else {
                VStack(spacing: 14) {
                    Button("Passer") {
                        finishRest()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .overlay(
                        Capsule().strokeBorder(Color.primary.opacity(0.4), lineWidth: 1)
                    )
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    Button("-10 s") {
                        restRemaining = max(0, restRemaining - 10)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.secondary)
                }
                .padding(.top, 8)
            }
            Spacer()
        }
        .padding(.top, 60)
    }

    // MARK: - Summary

    private var summaryView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(accentColor)
            Text("Séance terminée")
                .font(.title.bold())
                .foregroundStyle(Color.primary)
            Text("Bravo !")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Durée : \(formatElapsed(Int(Date().timeIntervalSince(startDate))))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if totalVolumeAccumulated > 0 {
                Text("Volume : \(Int(totalVolumeAccumulated)) kg")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button {
                dismiss()
            } label: {
                Text("Terminer")
                    .font(.headline)
                    .foregroundStyle(textOnAccentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
            Spacer()
        }
        .padding(.top, 60)
    }

    // MARK: - Helpers

    private func formatElapsed(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func startExecutionChrono() {
        executionElapsedSeconds = 0
        executionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                executionElapsedSeconds += 1
            }
        }
        RunLoop.main.add(executionTimer!, forMode: .common)
    }

    private func validateSet(reps: Int, weight: Double, isPR: Bool) {
        totalVolumeAccumulated += Double(reps) * weight

        let progName = isAtomique ? programName : (program?.name ?? programName)
        let phase = isAtomique ? weekNumber : phaseIndex
        let day = isAtomique ? dayIndex : dayIndexLegacy
        let exName = currentItem?.exerciseName ?? ""

        let estimated1RM = OneRMHelper.estimatedOneRM(weight: weight, reps: reps) ?? 0

        let log = WorkoutLog(
            date: .now,
            programName: progName,
            phaseIndex: phase,
            dayIndex: day,
            exerciseName: exName,
            setIndex: currentSetIndex,
            targetReps: currentItem?.targetReps ?? "",
            targetWeight: "",
            actualReps: reps,
            actualWeight: weight
        )
        context.insert(log)

        let master = currentItem?.exerciseMaster
        let setResult = ExerciseSetResult(
            date: .now,
            exerciseName: exName,
            setIndex: currentSetIndex,
            reps: reps,
            weight: weight,
            estimatedOneRM: estimated1RM,
            exercise: master,
            user: userProfile
        )
        context.insert(setResult)
        setResult.user = userProfile
        setResult.exercise = master
        if let master = master, isPR, estimated1RM > master.estimatedOneRM {
            master.estimatedOneRM = estimated1RM
        }
        try? context.save()

        let restSec = currentItem?.restSeconds ?? 60
        startRest(restSeconds: restSec)
    }

    private func startRest(restSeconds: Int) {
        executionTimer?.invalidate()
        restTimer?.invalidate()
        restRemaining = restSeconds
        state = .restTimer
        restJustEnded = false

        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                if restRemaining > 0 {
                    restRemaining -= 1
                } else {
                    restTimer?.invalidate()
                    if !restJustEnded {
                        restJustEnded = true
                        playRestEndAlarm()
                    }
                }
            }
        }
        RunLoop.main.add(restTimer!, forMode: .common)
    }

    private func playRestEndAlarm() {
        AudioServicesPlaySystemSound(1005)
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
    }

    private func finishRest() {
        restTimer?.invalidate()
        if currentSetIndex < totalSetsForExercise {
            currentSetIndex += 1
            executionElapsedSeconds = 0
            startExecutionChrono()
            state = .exerciseActive
        } else if currentExerciseIndex + 1 < runnerItems.count {
            currentExerciseIndex += 1
            currentSetIndex = 1
            totalSetsForExercise = runnerItems[currentExerciseIndex].sets
            executionElapsedSeconds = 0
            startExecutionChrono()
            state = .exerciseActive
        } else {
            completeSession()
        }
    }

    private func completeSession() {
        let totalDuration = Int(Date().timeIntervalSince(startDate))
        let session = WorkoutHistorySession(
            date: .now,
            programName: programName,
            phaseIndex: isAtomique ? weekNumber : phaseIndex,
            dayIndex: isAtomique ? dayIndex : dayIndexLegacy,
            completionPercentage: 100,
            averageRestTimeSeconds: 60,
            totalDurationSeconds: totalDuration,
            totalVolumeKg: totalVolumeAccumulated,
            isCompleted: true,
            isSkipped: false
        )
        session.program = program
        context.insert(session)

        if let profile = userProfile {
            profile.lastWorkoutDate = .now
            profile.lastWorkoutDurationSeconds = totalDuration
            profile.lastWorkoutTotalVolumeKg = totalVolumeAccumulated
        }

        try? context.save()
        state = .summary
    }
}
