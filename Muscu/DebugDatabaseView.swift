//
//  DebugDatabaseView.swift
//  Muscu
//
//  Rôle : Vue de diagnostic SwiftData (liste UserProfile, TrainingProgram, audit semaines/jours, bouton « Assigner au Profil »).
//  Utilisé par : WorkoutView (sheet via bouton coccinelle).
//

import SwiftUI
import SwiftData

struct DebugDatabaseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query private var profiles: [UserProfile]
    @Query(sort: \TrainingProgram.name) private var programs: [TrainingProgram]

    var body: some View {
        NavigationStack {
            List {
                profileSection
                programsSection
                weeksDaysAuditSection
            }
            .navigationTitle("Debug Base de données")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    // MARK: - Section PROFIL

    private var profileSection: some View {
        Section {
            if profiles.isEmpty {
                Text("Aucun UserProfile en base.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(profiles, id: \.persistentModelID) { profile in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Profil (id: \(profile.persistentModelID.hashValue))")
                            .font(.headline)
                        Text("name: — (propriété absente du modèle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("age: \(profile.age)")
                        Text("activeTrainingProgram: \(profile.activeTrainingProgram?.name ?? "Nil")")
                            .fontWeight(.medium)
                            .foregroundStyle(profile.activeTrainingProgram == nil ? .orange : .primary)
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("PROFIL")
        }
    }

    // MARK: - Section PROGRAMMES

    private var programsSection: some View {
        Section {
            if programs.isEmpty {
                Text("Aucun TrainingProgram en base.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(programs, id: \.persistentModelID) { program in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(program.name)
                                .font(.headline)
                            Text("Semaines: \(program.weeks.count)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Assigner au Profil") {
                            assignProgramToProfile(program)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("PROGRAMMES")
        }
    }

    private func assignProgramToProfile(_ program: TrainingProgram) {
        guard let profile = profiles.first else {
            print("[Debug] Aucun profil pour assigner le programme.")
            return
        }
        profile.activeTrainingProgram = program
        do {
            try context.save()
            print("[Debug] Programme « \(program.name) » assigné au profil.")
        } catch {
            print("[Debug] Erreur save: \(error)")
        }
    }

    // MARK: - Section SEMAINES / JOURS (Audit)

    private var weeksDaysAuditSection: some View {
        Section {
            if programs.isEmpty {
                Text("Aucun programme à auditer.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(programs, id: \.persistentModelID) { program in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(program.name)
                            .font(.headline)
                        if let firstWeek = program.weeks.first {
                            Text("Première semaine (n°\(firstWeek.weekNumber)): days.count = \(firstWeek.days.count)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Aucune semaine (coquille vide).")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("SEMAINES / JOURS (Audit)")
        }
    }
}

#Preview {
    DebugDatabaseView()
        .modelContainer(for: [UserProfile.self, TrainingProgram.self], inMemory: true)
}
