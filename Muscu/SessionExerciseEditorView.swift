//
//  SessionExerciseEditorView.swift
//  Muscu
//
//  Vue d’édition complète d’un SessionExercise (présentée en sheet depuis DayEditorView).
//

import SwiftUI
import SwiftData

struct SessionExerciseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var sessionExercise: SessionExercise

    @State private var showExercisePicker = false

    var body: some View {
        NavigationStack {
            Form {
                exerciseSection
                volumeSection
                loadSection
            }
            .navigationTitle("Modifier l’exercice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        saveAndDismiss()
                    }
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

    // MARK: - Section Exercice de base

    private var exerciseSection: some View {
        Section {
            if let master = sessionExercise.exercise {
                HStack(spacing: 14) {
                    Image(systemName: master.visualAsset)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 48, height: 48)
                        .background(Color(.tertiarySystemFill))
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
                .padding(.vertical, 4)

                Button {
                    showExercisePicker = true
                } label: {
                    Label("Changer l’exercice", systemImage: "arrow.triangle.2.circlepath")
                }
            } else {
                Button {
                    showExercisePicker = true
                } label: {
                    Label("Choisir un exercice", systemImage: "plus.circle.fill")
                }
            }
        } header: {
            Text("Exercice")
        }
    }

    // MARK: - Section Volume / Paramètres de séance

    private var volumeSection: some View {
        Section {
            Stepper("Séries : \(sessionExercise.sets)", value: $sessionExercise.sets, in: 1...20)
            TextField("Reps (ex: 10, 8-12, Failure)", text: $sessionExercise.reps)
                .keyboardType(.default)
            Stepper("Repos : \(sessionExercise.restTime) s", value: $sessionExercise.restTime, in: 0...300, step: 15)
        } header: {
            Text("Paramètres de séance")
        }
    }

    // MARK: - Section Charge

    private var loadSection: some View {
        Section {
            Picker("Stratégie de charge", selection: $sessionExercise.loadStrategy) {
                ForEach(LoadStrategy.allCases, id: \.self) { s in
                    Text(loadStrategyLabel(s)).tag(s)
                }
            }
            .pickerStyle(.menu)

            HStack {
                Text(loadValueLabel)
                TextField("0", value: $sessionExercise.loadValue, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("Charge")
        }
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
