//
//  SessionExerciseEditorView.swift
//  Muscu
//
//  Rôle : Formulaire d'édition complète d'un SessionExercise (exercice de base, séries, repos, charge).
//  DA Elite Athlete : ScrollView + cartes, accentColor, fond adaptatif.
//

import SwiftUI
import SwiftData

private let SessionEditorBgDark = Color(red: 15/255, green: 17/255, blue: 21/255)
private let SessionEditorCardDark = Color(red: 28/255, green: 31/255, blue: 38/255)

struct SessionExerciseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentColor) private var accentColor
    @Environment(\.textOnAccentColor) private var textOnAccentColor
    @Bindable var sessionExercise: SessionExercise

    @State private var showExercisePicker = false

    private var pageBackground: Color {
        colorScheme == .dark ? SessionEditorBgDark : Color(.systemGroupedBackground)
    }
    private var cardBackground: Color {
        colorScheme == .dark ? SessionEditorCardDark : Color(.secondarySystemGroupedBackground)
    }
    private var cardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.gray.opacity(0.2)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    exerciseCard
                    volumeCard
                    loadCard
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            .scrollContentBackground(.hidden)
            .background(pageBackground)
            .navigationTitle("Modifier l’exercice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .foregroundStyle(accentColor)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        saveAndDismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(colorScheme == .light ? .black : textOnAccentColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(accentColor)
                    .clipShape(Capsule())
                }
            }
            .sheet(isPresented: $showExercisePicker) {
                ExercisePickerView { master in
                    sessionExercise.exercise = master
                    showExercisePicker = false
                }
            }
        }
    }

    private var exerciseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exercice")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if let master = sessionExercise.exercise {
                HStack(spacing: 14) {
                    Image(systemName: master.visualAsset)
                        .font(.title2)
                        .foregroundStyle(accentColor)
                        .frame(width: 48, height: 48)
                        .background(accentColor.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(master.name)
                            .font(.headline)
                        if !master.musclesTargeted.isEmpty {
                            Text(master.musclesTargeted.map(\.rawValue).joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                Button {
                    showExercisePicker = true
                } label: {
                    Label("Changer l’exercice", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline)
                        .foregroundStyle(accentColor)
                }
            } else {
                Button {
                    showExercisePicker = true
                } label: {
                    Label("Choisir un exercice", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .foregroundStyle(colorScheme == .light ? .black : textOnAccentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(cardBorder, lineWidth: 0.5))
    }

    private var volumeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paramètres de séance")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Stepper("Séries : \(sessionExercise.sets)", value: $sessionExercise.sets, in: 1...20)
                .tint(accentColor)
            TextField("Reps (ex: 10, 8-12, Failure)", text: $sessionExercise.reps)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.default)
            Stepper("Repos : \(sessionExercise.restTime) s", value: $sessionExercise.restTime, in: 0...300, step: 15)
                .tint(accentColor)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(cardBorder, lineWidth: 0.5))
    }

    private var loadCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Charge")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("Stratégie de charge", selection: $sessionExercise.loadStrategy) {
                ForEach(LoadStrategy.allCases, id: \.self) { s in
                    Text(loadStrategyLabel(s)).tag(s)
                }
            }
            .pickerStyle(.menu)
            .accentColor(accentColor)
            HStack {
                Text(loadValueLabel)
                TextField("0", value: $sessionExercise.loadValue, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(cardBorder, lineWidth: 0.5))
    }

    private var loadValueLabel: String {
        switch sessionExercise.loadStrategy {
        case .fixedWeight: return "Charge (kg)"
        case .percentageOfOneRM: return "% 1RM"
        case .rpe: return "RPE (1-10)"
        }
    }

    private func loadStrategyLabel(_ s: LoadStrategy) -> String {
        switch s {
        case .fixedWeight: return "Poids fixe"
        case .percentageOfOneRM: return "% du 1RM"
        case .rpe: return "RPE"
        }
    }

    private func saveAndDismiss() {
        try? context.save()
        dismiss()
    }
}

#Preview {
    SessionExerciseEditorView(sessionExercise: SessionExercise(sets: 3, reps: "10", restTime: 60, loadStrategy: .fixedWeight, loadValue: 0))
        .modelContainer(for: [SessionExercise.self, ExerciseMaster.self], inMemory: true)
}
