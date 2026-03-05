//
//  NewProgramSheet.swift
//  Muscu
//
//  Rôle : Formulaire de création d'un programme (nom, catégorie SportCategory) ; appelle DataController.createNewProgram au validement.
//  Utilisé par : WorkoutView (sheet « Ajouter un programme »).
//

import SwiftUI

struct NewProgramSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selectedCategory: SportCategory = .bodybuilding

    /// Callback vers le parent : crée effectivement le programme.
    var onCreate: (String, SportCategory) -> Void

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom du programme", text: $name)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Nom")
                }

                Section {
                    Picker("Catégorie principale", selection: $selectedCategory) {
                        ForEach(SportCategory.allCases, id: \.self) { cat in
                            Text(label(for: cat)).tag(cat)
                        }
                    }
                } header: {
                    Text("Objectif / Sport")
                }
            }
            .navigationTitle("Nouveau Programme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer et Commencer") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onCreate(trimmed, selectedCategory)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private func label(for category: SportCategory) -> String {
        switch category {
        case .bodybuilding: return "Musculation"
        case .volley: return "Volley"
        case .basket: return "Basket"
        case .running: return "Course à pied"
        case .boxing: return "Boxe"
        case .general: return "Général / Hybride"
        }
    }
}

#Preview {
    NewProgramSheet { _, _ in }
}

