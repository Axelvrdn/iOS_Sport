//
//  ProgramListView.swift
//  Muscu
//
//  Rôle : Liste des programmes atomiques filtrés selon la discipline choisie dans le profil.
//

import SwiftUI
import SwiftData

struct ProgramListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingProgram.name) private var programs: [TrainingProgram]
    @Query private var profiles: [UserProfile]

    private var userDisciplines: Set<Discipline> {
        profiles.first?.selectedDisciplines ?? [.strength]
    }

    /// Mapping disciplines → catégories de sport associées.
    private func categories(for disciplines: Set<Discipline>) -> Set<SportCategory> {
        disciplines.reduce(into: Set<SportCategory>()) { acc, d in
            switch d {
            case .combat:
                acc.insert(.boxing)
            case .endurance:
                acc.insert(.running)
            case .racket:
                acc.insert(.general)
            case .outdoor:
                acc.insert(.general)
            case .wellness:
                acc.insert(.general)
            case .strength:
                acc.insert(.bodybuilding)
            case .street:
                acc.insert(.bodybuilding)
            case .ballSports:
                acc.insert(.basket); acc.insert(.volley)
            }
        }
    }

    private var filteredPrograms: [TrainingProgram] {
        let wanted = categories(for: userDisciplines)
        return programs.filter { program in
            // Ne pas afficher les gabarits (templates) dans "Mes Programmes".
            guard !program.isTemplate else { return false }
            let cats = Set(program.sportCategories)
            // Universel : contient .general → toujours visible
            if cats.contains(.general) { return true }
            return !cats.isDisjoint(with: wanted)
        }
    }

    var body: some View {
        List {
            ForEach(filteredPrograms) { program in
                VStack(alignment: .leading, spacing: 4) {
                    Text(program.name)
                        .font(.headline)
                    if !program.programDescription.isEmpty {
                        Text(program.programDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Mes Programmes")
    }
}

