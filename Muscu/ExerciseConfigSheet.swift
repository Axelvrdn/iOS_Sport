//
//  ExerciseConfigSheet.swift
//  Muscu
//
//  Rôle : Configuration d'un nouveau SessionExercise (séries, reps, repos, charge) avant ajout à une SessionRecipe.
//  Utilisé par : DayEditorView (sheet après sélection d'un ExerciseMaster dans ExercisePickerView).
//

import SwiftUI
import SwiftData

struct ExerciseConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let master: ExerciseMaster
    let sessionRecipe: SessionRecipe

    @State private var sets: Int = 3
    @State private var reps: String = "10"
    @State private var restTime: Int = 60
    @State private var loadStrategy: LoadStrategy = .fixedWeight
    @State private var loadValue: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Exercice", value: master.name)
                    LabeledContent("Repos par défaut", value: "\(master.defaultRestTime) s")
                } header: {
                    Text("Référence")
                }

                Section {
                    Stepper("Séries : \(sets)", value: $sets, in: 1...20)
                    TextField("Reps (ex: 10, 8-12, Failure)", text: $reps)
                        .keyboardType(.default)
                    Stepper("Repos : \(restTime) s", value: $restTime, in: 0...300, step: 15)
                } header: {
                    Text("Volume")
                }

                Section {
                    Picker("Stratégie de charge", selection: $loadStrategy) {
                        ForEach(LoadStrategy.allCases, id: \.self) { s in
                            Text(loadStrategyLabel(s)).tag(s)
                        }
                    }
                    .pickerStyle(.menu)

                    switch loadStrategy {
                    case .fixedWeight:
                        HStack {
                            Text("Charge (kg)")
                            TextField("0", value: $loadValue, format: .number)
                                .keyboardType(.decimalPad)
                        }
                    case .percentageOfOneRM:
                        HStack {
                            Text("% 1RM")
                            TextField("75", value: $loadValue, format: .number)
                                .keyboardType(.decimalPad)
                        }
                    case .rpe:
                        HStack {
                            Text("RPE (1-10)")
                            TextField("8", value: $loadValue, format: .number)
                                .keyboardType(.decimalPad)
                        }
                    }
                } header: {
                    Text("Charge")
                }
            }
            .navigationTitle("Configurer l’exercice")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                restTime = master.defaultRestTime
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        addSessionExercise()
                        dismiss()
                    }
                }
            }
        }
    }

    private func loadStrategyLabel(_ s: LoadStrategy) -> String {
        switch s {
        case .fixedWeight: return "Poids fixe"
        case .percentageOfOneRM: return "% du 1RM"
        case .rpe: return "RPE"
        }
    }

    private func addSessionExercise() {
        let se = SessionExercise(
            sets: sets,
            reps: reps.isEmpty ? "10" : reps,
            restTime: restTime,
            loadStrategy: loadStrategy,
            loadValue: loadValue
        )
        se.exercise = master
        se.session = sessionRecipe
        context.insert(se)
        sessionRecipe.exercises.append(se)
        try? context.save()
    }
}
