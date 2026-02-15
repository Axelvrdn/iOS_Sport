//
//  ProgramDetailView.swift
//  Muscu
//
//  Detailed view for a WorkoutProgram, including phases, weeks
//  and exercises with optional bodyweight alternatives.
//

import SwiftUI
import SwiftData

struct ProgramDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    @State private var noEquipmentMode: Bool = false

    /// Programme affiché (SwiftData `WorkoutProgram` passé en paramètre)
    /// Pas besoin d’attribut spécial ici, on l’utilise en lecture seule.
    var program: WorkoutProgram

    // Group exercises by phase and day
    private var groupedByPhaseAndDay: [Int: [Int: [Exercise]]] {
        var result: [Int: [Int: [Exercise]]] = [:]
        for ex in program.exercises {
            result[ex.phaseIndex, default: [:]][ex.dayIndex, default: []].append(ex)
        }
        // trier par nom dans chaque jour
        for phase in result.keys {
            for day in result[phase]!.keys {
                result[phase]![day] = result[phase]![day]!.sorted { $0.name < $1.name }
            }
        }
        return result
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(program.name)
                        .font(.title2.bold())
                    Text("Auteur : \(program.author)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Type : \(program.type) • Difficulté : \(program.difficulty)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                Toggle("Mode sans matériel", isOn: $noEquipmentMode)
            }

            ForEach(Array(groupedByPhaseAndDay.keys).sorted(), id: \.self) { phase in
                Section(header: Text("Phase \(phase)")) {
                    // Weeks: 1-4 for Phase 1, 5-8 for Phase 2, etc.
                    let startWeek = (phase - 1) * 4 + 1
                    let endWeek = startWeek + 3

                    ForEach(startWeek...endWeek, id: \.self) { week in
                        DisclosureGroup("Semaine \(week)") {
                            if let days = groupedByPhaseAndDay[phase] {
                                ForEach(days.keys.sorted(), id: \.self) { dayIndex in
                                    if let exercises = days[dayIndex],
                                       let first = exercises.first {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(first.dayName)
                                                .font(.headline)
                                            Text(first.dayFocus)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)

                                            ForEach(exercises) { exercise in
                                                exerciseRow(for: exercise)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Programme")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Subviews

    @ViewBuilder
    private func exerciseRow(for exercise: Exercise) -> some View {
        let displayExercise: Exercise = {
            if noEquipmentMode,
               exercise.equipmentRequired,
               let alt = exercise.alternativeExercise {
                return alt
            }
            return exercise
        }()

        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(displayExercise.name)
                        .font(.subheadline.bold())
                    if displayExercise.isBonus {
                        Text("Bonus")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(4)
                    }
                }

                Text(displayExercise.setsRepsDescription)
                    .font(.caption)
                Text("Repos : \(displayExercise.restSeconds) s")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if noEquipmentMode,
                   exercise.equipmentRequired,
                   let _ = exercise.alternativeExercise {
                    Text("Version sans matériel utilisée à la place de \(exercise.name).")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else if exercise.equipmentRequired {
                    Text("Nécessite du matériel")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Sans matériel")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            if let urlString = displayExercise.videoUrl,
               let url = URL(string: urlString) {
                openURL(url)
            }
        }
    }
}

