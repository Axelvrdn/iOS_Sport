//
//  ExercisePickerView.swift
//  Muscu
//
//  Rôle : Liste des ExerciseMaster avec visuel ; sélection renvoie le master puis ouvre la configuration (ExerciseConfigSheet).
//  Utilisé par : DayEditorView, SessionExerciseEditorView (changer l'exercice).
//

import SwiftUI
import SwiftData

// MARK: - Exercise Picker (liste des masters)

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ExerciseMaster.name) private var masters: [ExerciseMaster]
    var onSelect: (ExerciseMaster) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if masters.isEmpty {
                    ContentUnavailableView(
                        "Aucun exercice",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("La bibliothèque sera remplie par le seeder au premier lancement.")
                    )
                } else {
                    List(masters) { master in
                        Button {
                            onSelect(master)
                            dismiss()
                        } label: {
                            ExerciseMasterRow(master: master)
                        }
                    }
                }
            }
            .navigationTitle("Choisir un exercice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Row (image + nom + muscles)

private struct ExerciseMasterRow: View {
    let master: ExerciseMaster

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: master.visualAsset)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(master.name)
                    .font(.subheadline.bold())
                if !master.musclesTargeted.isEmpty {
                    Text(master.musclesTargeted.map(\.rawValue).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
