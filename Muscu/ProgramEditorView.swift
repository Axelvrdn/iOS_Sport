//
//  ProgramEditorView.swift
//  Muscu
//
//  Dashboard "Framework-style" pour éditer un programme (semaines / jours variables).
//

import SwiftUI
import SwiftData

struct ProgramEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var program: TrainingProgram
    /// Semaines dépliées (accordéon) — identifiées par weekNumber.
    @State private var expandedWeekNumbers: Set<Int> = []

    private var scheduleWarnings: [ScheduleWarning] {
        ProgramManager.validateSchedule(program: program)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Avertissements du validateur
                    if !scheduleWarnings.isEmpty {
                        ScheduleWarningsBanner(warnings: scheduleWarnings)
                            .padding(.horizontal)
                    }

                    // Header: titre éditable
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Nom du programme", text: Binding(
                            get: { program.name },
                            set: { program.name = $0; try? context.save() }
                        ))
                        .font(.title2.bold())

                        TextField("Description", text: Binding(
                            get: { program.programDescription },
                            set: { program.programDescription = $0; try? context.save() }
                        ), axis: .vertical)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2...4)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Cartes des semaines (accordéon)
                    let weeks = program.weeks.sorted { $0.weekNumber < $1.weekNumber }
                    ForEach(weeks) { week in
                        WeekCardView(
                            week: week,
                            isExpanded: expandedWeekNumbers.contains(week.weekNumber),
                            onToggle: { expandedWeekNumbers.formSymmetricDifference([week.weekNumber]) }
                        )
                    }

                    // Bouton en bas du contenu (visible après scroll, au-dessus de la TabBar)
                    Button {
                        addWeek()
                    } label: {
                        Label("Ajouter une semaine", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .padding(.bottom, 150)
            }
            .contentMargins(.bottom, 150, for: .scrollContent)
        }
        .navigationTitle("Éditeur de programme")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addWeek() {
        let nextNumber = (program.weeks.map(\.weekNumber).max() ?? 0) + 1
        let week = TrainingWeek(weekNumber: nextNumber)
        week.program = program
        context.insert(week)
        program.weeks.append(week)
        try? context.save()
    }
}

// MARK: - Week Card (Accordéon : clic pour déplier, bulles de jours à l’intérieur)

private struct WeekCardView: View {
    @Environment(\.modelContext) private var context
    @Bindable var week: TrainingWeek
    var isExpanded: Bool
    var onToggle: () -> Void
    @State private var dragVersion: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // En-tête cliquable (toggle accordéon) + menu
            Button {
                onToggle()
            } label: {
                HStack {
                    Text("Semaine \(week.weekNumber)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack {
                Spacer()
                Menu {
                    Button(role: .destructive) {
                        deleteWeek()
                    } label: {
                        Label("Supprimer la semaine", systemImage: "trash")
                    }
                    Button {
                        duplicateWeek()
                    } label: {
                        Label("Dupliquer la semaine", systemImage: "doc.on.doc")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Menu Éditer la semaine")
            }
            .padding(.top, 4)

            // Zone dépliée : liste horizontale de bulles de jours (Lun–Dim style)
            if isExpanded {
                let days = week.days.sorted { $0.dayIndex < $1.dayIndex }
                VStack(alignment: .leading, spacing: 12) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(days) { day in
                                NavigationLink {
                                    DayEditorView(day: day)
                                } label: {
                                    DayBubbleView(day: day)
                                }
                                .buttonStyle(.plain)
                                // Menu contextuel : supprimer ce jour
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deleteDay(day, in: week)
                                    } label: {
                                        Label("Supprimer ce jour", systemImage: "trash")
                                    }
                                }
                                // Drag & drop horizontal basé sur le dayIndex (String transférable)
                                .draggable(String(day.dayIndex))
                                .dropDestination(for: String.self) { items, _ in
                                    guard
                                        let raw = items.first,
                                        let sourceIndex = Int(raw)
                                    else { return false }
                                    swapDayIndices(from: sourceIndex, to: day.dayIndex, in: week)
                                    return true
                                }
                            }
                            // Bouton + visible uniquement si la semaine a moins de 7 jours
                            if days.count < 7 {
                                Button {
                                    addDay()
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Ajouter un jour")
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                    }
                    .animation(.default, value: dragVersion)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func addDay() {
        // Contrainte : maximum 7 jours par semaine
        guard week.days.count < 7 else { return }
        let nextIndex = (week.days.map(\.dayIndex).max() ?? -1) + 1
        let day = TrainingDay(
            dayIndex: nextIndex,
            isRestDay: false,
            focusCategory: .none,
            title: "Jour \(nextIndex + 1)"
        )
        day.week = week
        context.insert(day)
        week.days.append(day)
        try? context.save()
    }

    private func deleteDay(_ day: TrainingDay, in week: TrainingWeek) {
        // Supprime le jour et réindexe les jours restants (0,1,2,…)
        week.days.removeAll { $0.persistentModelID == day.persistentModelID }
        context.delete(day)
        let sorted = week.days.sorted { $0.dayIndex < $1.dayIndex }
        for (idx, d) in sorted.enumerated() {
            d.dayIndex = idx
        }
        try? context.save()
        dragVersion &+= 1
    }

    private func swapDayIndices(from sourceIndex: Int, to targetIndex: Int, in week: TrainingWeek) {
        guard sourceIndex != targetIndex else { return }
        guard
            let sourceDay = week.days.first(where: { $0.dayIndex == sourceIndex }),
            let targetDay = week.days.first(where: { $0.dayIndex == targetIndex })
        else { return }

        let tmp = sourceDay.dayIndex
        sourceDay.dayIndex = targetDay.dayIndex
        targetDay.dayIndex = tmp

        try? context.save()
        dragVersion &+= 1
    }

    private func deleteWeek() {
        guard let program = week.program else { return }
        program.weeks.removeAll { $0.persistentModelID == week.persistentModelID }
        context.delete(week)
        try? context.save()
    }

    private func duplicateWeek() {
        guard let program = week.program else { return }
        let newNumber = (program.weeks.map(\.weekNumber).max() ?? 0) + 1
        let newWeek = TrainingWeek(weekNumber: newNumber)
        newWeek.program = program
        context.insert(newWeek)
        program.weeks.append(newWeek)

        for d in week.days.sorted(by: { $0.dayIndex < $1.dayIndex }) {
            let newDay = TrainingDay(
                dayIndex: d.dayIndex,
                isRestDay: d.isRestDay,
                focusCategory: d.focusCategory,
                title: d.title
            )
            newDay.week = newWeek
            context.insert(newDay)
            newWeek.days.append(newDay)
            for ex in d.exercises {
                let copy = Exercise(
                    name: ex.name,
                    targetMuscleGroup: ex.targetMuscleGroup,
                    setsRepsDescription: ex.setsRepsDescription,
                    restSeconds: ex.restSeconds,
                    equipmentRequired: ex.equipmentRequired,
                    isBonus: ex.isBonus,
                    phaseIndex: ex.phaseIndex,
                    dayIndex: ex.dayIndex,
                    dayName: ex.dayName,
                    dayFocus: ex.dayFocus,
                    videoUrl: ex.videoUrl,
                    alternativeExercise: nil
                )
                context.insert(copy)
                copy.trainingDay = newDay
                newDay.exercises.append(copy)
            }
        }
        try? context.save()
    }
}

// MARK: - Day Bubble (cercle coloré selon focus — utilisé dans l’accordéon des semaines)

private struct DayBubbleView: View {
    @Bindable var day: TrainingDay

    var body: some View {
        VStack(spacing: 4) {
            Text("\(day.dayIndex + 1)")
                .font(.caption.bold())
                .frame(width: 40, height: 40)
                .background(bubbleColor)
                .foregroundStyle(.primary)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 1))

            Text(day.title.isEmpty ? "J\(day.dayIndex + 1)" : day.title)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .frame(width: 56)
    }

    private var bubbleColor: Color {
        if day.isRestDay { return Color.gray.opacity(0.25) }
        switch day.focusCategory {
        case .lowerBody, .legs: return Color.green.opacity(0.3)
        case .upperBody, .push, .pull: return Color.blue.opacity(0.3)
        case .plyometrics: return Color.orange.opacity(0.3)
        case .cardio: return Color.purple.opacity(0.3)
        case .hybrid: return Color.teal.opacity(0.3)
        case .none: return Color.yellow.opacity(0.2)
        }
    }
}

// MARK: - Day Card Row (style carte : fond arrondi, ombre, icône FocusCategory)

private struct DayCardRow: View {
    @Bindable var day: TrainingDay

    var body: some View {
        HStack(spacing: 14) {
            // Icône / pastille catégorie
            Image(systemName: focusIcon)
                .font(.title3)
                .foregroundStyle(focusColor)
                .frame(width: 44, height: 44)
                .background(focusColor.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(day.title.isEmpty ? "J\(day.dayIndex + 1)" : day.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Text(focusCategoryLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }

    private var focusIcon: String {
        if day.isRestDay { return "bed.double.fill" }
        switch day.focusCategory {
        case .lowerBody, .legs: return "figure.run"
        case .upperBody, .push, .pull: return "figure.arms.open"
        case .plyometrics: return "flame.fill"
        case .cardio: return "heart.fill"
        case .hybrid: return "square.stack.3d.up.fill"
        case .none: return "circle.dashed"
        }
    }

    private var focusColor: Color {
        if day.isRestDay { return .gray }
        switch day.focusCategory {
        case .lowerBody, .legs: return .green
        case .upperBody, .push, .pull: return .blue
        case .plyometrics: return .orange
        case .cardio: return .purple
        case .hybrid: return .teal
        case .none: return .yellow
        }
    }

    private var focusCategoryLabel: String {
        if day.isRestDay { return "Repos" }
        switch day.focusCategory {
        case .lowerBody: return "Lower Body"
        case .upperBody: return "Upper Body"
        case .plyometrics: return "Plyométrie"
        case .push: return "Push"
        case .pull: return "Pull"
        case .legs: return "Jambes"
        case .cardio: return "Cardio"
        case .hybrid: return "Hybride"
        case .none: return "Non défini"
        }
    }
}

// MARK: - Wrapper for sheet(item:)

private struct MasterWrapper: Identifiable, Equatable {
    let id = UUID()
    let master: ExerciseMaster

    static func == (lhs: MasterWrapper, rhs: MasterWrapper) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Day Editor (Leaf View)

struct DayEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var day: TrainingDay

    @State private var showExercisePicker = false
    @State private var configTarget: MasterWrapper?
    @State private var showConfigSheet = false
    @State private var exerciseToEdit: SessionExercise?
    @State private var showExerciseEditor = false

    private static let presetExercises: [(name: String, target: String, scheme: String, focus: FocusCategory)] = [
        ("Squat", "Quadriceps / Fessiers", "3x10", .lowerBody),
        ("Bench Press", "Poitrine / Triceps", "3x10", .push),
        ("Deadlift", "Dos / Ischios", "3x8", .pull),
        ("Overhead Press", "Épaules", "3x10", .push),
        ("Row", "Dos", "3x10", .pull),
        ("Lunges", "Jambes", "3x10", .legs),
        ("Jump Squat", "Plyométrie", "3x8", .plyometrics),
        ("Burpees", "Full Body", "3x10", .cardio),
        ("Plank", "Core", "3x30s", .hybrid),
    ]

    var body: some View {
        List {
            Section("Focus du jour") {
                Picker("Catégorie", selection: Binding(
                    get: { day.focusCategory },
                    set: { day.focusCategory = $0; day.isRestDay = ($0 == .none); try? context.save() }
                )) {
                    ForEach(FocusCategory.allCases, id: \.self) { cat in
                        Text(displayName(cat)).tag(cat)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Jour de repos", isOn: Binding(
                    get: { day.isRestDay },
                    set: { day.isRestDay = $0; if $0 { day.focusCategory = .none }; try? context.save() }
                ))

                TextField("Titre du jour", text: Binding(
                    get: { day.title },
                    set: { day.title = $0; try? context.save() }
                ))
            }

            // Séance atomique (SessionRecipe + ExerciseMaster)
            if day.sessionRecipe != nil {
                sessionRecipeSection
            } else {
                Section("Séance (système atomique)") {
                    Button {
                        createSessionRecipe()
                    } label: {
                        Label("Créer une séance (recette)", systemImage: "plus.circle.fill")
                    }
                }
            }

            Section("Exercices (legacy)") {
                ForEach(day.exercises) { ex in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.name).font(.subheadline.bold())
                            Text(ex.setsRepsDescription).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { indexSet in
                    for i in indexSet.sorted(by: >) {
                        let ex = day.exercises[i]
                        context.delete(ex)
                        day.exercises.remove(at: i)
                    }
                    try? context.save()
                }

                Menu {
                    ForEach(Self.presetExercises, id: \.name) { preset in
                        Button(preset.name) {
                            addPresetExercise(preset)
                        }
                    }
                } label: {
                    Label("Ajouter depuis les presets", systemImage: "list.bullet")
                }

                Button {
                    replicatePreviousDay()
                } label: {
                    Label("Répliquer le jour précédent", systemImage: "doc.on.doc.fill")
                }
            }
        }
        .navigationTitle(day.title.isEmpty ? "Jour \(day.dayIndex + 1)" : day.title)
        .sheet(isPresented: $showExercisePicker) {
            if let recipe = day.sessionRecipe {
                ExercisePickerView { master in
                    configTarget = MasterWrapper(master: master)
                    showExercisePicker = false
                }
            }
        }
        .onChange(of: configTarget) { _, new in
            if new != nil { showConfigSheet = true }
        }
        .sheet(isPresented: $showConfigSheet) {
            if let w = configTarget, let recipe = day.sessionRecipe {
                ExerciseConfigSheet(master: w.master, sessionRecipe: recipe)
                    .onDisappear {
                        configTarget = nil
                        showConfigSheet = false
                    }
            }
        }
        .sheet(isPresented: $showExerciseEditor) {
            if let se = exerciseToEdit {
                SessionExerciseEditorView(sessionExercise: se)
                    .onDisappear {
                        exerciseToEdit = nil
                    }
            }
        }
    }

    private func deleteSessionExercise(_ se: SessionExercise, from recipe: SessionRecipe) {
        context.delete(se)
        recipe.exercises.removeAll { $0.persistentModelID == se.persistentModelID }
        try? context.save()
    }

    @ViewBuilder
    private var sessionRecipeSection: some View {
        if let recipe = day.sessionRecipe {
            Section("Séance (recette)") {
                TextField("Nom de la séance", text: Binding(
                    get: { recipe.name },
                    set: { recipe.name = $0; try? context.save() }
                ))
                Picker("Objectif", selection: Binding(
                    get: { recipe.goal },
                    set: { recipe.goal = $0; try? context.save() }
                )) {
                    ForEach(SessionGoal.allCases, id: \.self) { g in
                        Text(sessionGoalLabel(g)).tag(g)
                    }
                }
                .pickerStyle(.menu)
                Picker("Focus corps", selection: Binding(
                    get: { recipe.bodyFocus },
                    set: { recipe.bodyFocus = $0; try? context.save() }
                )) {
                    ForEach(BodyFocus.allCases, id: \.self) { b in
                        Text(b.rawValue.capitalized).tag(b)
                    }
                }
                .pickerStyle(.menu)

                ForEach(recipe.exercises) { se in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(se.exercise?.name ?? "—")
                                .font(.subheadline.bold())
                            Text("\(se.sets) × \(se.reps) · \(loadSummary(se))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteSessionExercise(se, from: recipe)
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                        Button {
                            exerciseToEdit = se
                            showExerciseEditor = true
                        } label: {
                            Label("Modifier", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }

                Button {
                    showExercisePicker = true
                } label: {
                    Label("Ajouter un exercice (bibliothèque)", systemImage: "plus.circle")
                }
            }
        }
    }

    private func sessionGoalLabel(_ g: SessionGoal) -> String {
        switch g {
        case .volume: return "Volume"
        case .strength: return "Force"
        case .technique: return "Technique"
        case .endurance: return "Endurance"
        case .rehab: return "Réhab"
        }
    }

    private func loadSummary(_ se: SessionExercise) -> String {
        switch se.loadStrategy {
        case .fixedWeight: return "\(Int(se.loadValue)) kg"
        case .percentageOfOneRM: return "\(Int(se.loadValue))% 1RM"
        case .rpe: return "RPE \(Int(se.loadValue))"
        }
    }

    private func createSessionRecipe() {
        let bodyFocus = bodyFocusFromFocusCategory(day.focusCategory)
        let recipe = SessionRecipe(
            name: day.title.isEmpty ? "Séance \(day.dayIndex + 1)" : day.title,
            goal: .volume,
            bodyFocus: bodyFocus,
            sportCategoriesString: SportCategory.bodybuilding.rawValue
        )
        context.insert(recipe)
        recipe.day = day
        day.sessionRecipe = recipe
        try? context.save()
    }

    private func bodyFocusFromFocusCategory(_ cat: FocusCategory) -> BodyFocus {
        switch cat {
        case .lowerBody, .legs: return .lower
        case .upperBody: return .upper
        case .push: return .push
        case .pull: return .pull
        case .plyometrics, .cardio, .hybrid: return .fullBody
        case .none: return .fullBody
        }
    }

    private func displayName(_ cat: FocusCategory) -> String {
        switch cat {
        case .lowerBody: return "Lower Body"
        case .upperBody: return "Upper Body"
        case .plyometrics: return "Plyométrie"
        case .push: return "Push"
        case .pull: return "Pull"
        case .legs: return "Jambes"
        case .cardio: return "Cardio"
        case .hybrid: return "Hybride"
        case .none: return "Aucun"
        }
    }

    private func addPresetExercise(_ preset: (name: String, target: String, scheme: String, focus: FocusCategory)) {
        let dayName = "Day \(day.dayIndex + 1)"
        let dayFocus = day.focusCategory.rawValue
        let ex = Exercise(
            name: preset.name,
            targetMuscleGroup: preset.target,
            setsRepsDescription: preset.scheme,
            restSeconds: 60,
            equipmentRequired: false,
            isBonus: false,
            phaseIndex: 1,
            dayIndex: day.dayIndex + 1,
            dayName: dayName,
            dayFocus: dayFocus,
            videoUrl: nil,
            alternativeExercise: nil
        )
        context.insert(ex)
        ex.trainingDay = day
        day.exercises.append(ex)
        try? context.save()
    }

    private func replicatePreviousDay() {
        // 1. Vérification : pas le jour 0
        guard day.dayIndex > 0, let week = day.week else { return }

        // 2. Récupération du jour précédent (index - 1)
        guard let previousDay = week.days.first(where: { $0.dayIndex == day.dayIndex - 1 }) else { return }

        var didCopy = false

        // 3a. Partie Legacy : copie des Exercise
        for ex in previousDay.exercises {
            let copy = Exercise(
                name: ex.name,
                targetMuscleGroup: ex.targetMuscleGroup,
                setsRepsDescription: ex.setsRepsDescription,
                restSeconds: ex.restSeconds,
                equipmentRequired: ex.equipmentRequired,
                isBonus: ex.isBonus,
                phaseIndex: ex.phaseIndex,
                dayIndex: day.dayIndex + 1,
                dayName: "Day \(day.dayIndex + 1)",
                dayFocus: day.focusCategory.rawValue,
                videoUrl: ex.videoUrl,
                alternativeExercise: nil
            )
            context.insert(copy)
            copy.trainingDay = day
            day.exercises.append(copy)
            didCopy = true
        }

        // 3b. Partie Atomique (CRUCIAL) : deep copy de SessionRecipe + SessionExercise
        if let sourceRecipe = previousDay.sessionRecipe {
            // Si le jour actuel a déjà une recette, la supprimer pour éviter doublon/orphelin
            if let existingRecipe = day.sessionRecipe {
                context.delete(existingRecipe)
                day.sessionRecipe = nil
            }
            let newRecipe = SessionRecipe(
                name: sourceRecipe.name,
                goal: sourceRecipe.goal,
                bodyFocus: sourceRecipe.bodyFocus,
                sportCategoriesString: sourceRecipe.sportCategoriesString
            )
            context.insert(newRecipe)
            newRecipe.day = day
            day.sessionRecipe = newRecipe

            for sourceSE in sourceRecipe.exercises {
                let newSE = SessionExercise(
                    sets: sourceSE.sets,
                    reps: sourceSE.reps,
                    restTime: sourceSE.restTime,
                    loadStrategy: sourceSE.loadStrategy,
                    loadValue: sourceSE.loadValue
                )
                context.insert(newSE)
                newSE.exercise = sourceSE.exercise
                newSE.session = newRecipe
                newRecipe.exercises.append(newSE)
            }
            didCopy = true
        }

        guard didCopy else { return }

        do {
            try context.save()
            // 5. Feedback
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            print("[DayEditorView] Jour précédent répliqué sur J\(day.dayIndex + 1).")
        } catch {
            print("[DayEditorView] Erreur save après réplication: \(error)")
        }
    }
}

// MARK: - Avertissements du validateur

private struct ScheduleWarningsBanner: View {
    let warnings: [ScheduleWarning]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(expanded ? "Masquer les avertissements" : warnings.first?.message ?? "Avertissements")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(warnings) { w in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                            Text(w.message)
                                .font(.caption)
                            if let week = w.weekNumber {
                                Text("(S\(week))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Empty State (aucun programme seedé)

struct ProgramEditorEmptyView: View {
    @Environment(\.modelContext) private var context
    @State private var isForcing = false
    @State private var showDoneAlert = false

    var body: some View {
        VStack(spacing: 24) {
            ContentUnavailableView(
            "Aucun programme",
            systemImage: "tray",
            description: Text("Le programme par défaut sera créé au lancement. Redémarrez l’app si besoin.")
            )
            Button {
                forceSeed()
            } label: {
                if isForcing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(height: 20)
                } else {
                    Text("Forcer la génération du Programme")
                }
            }
            .disabled(isForcing)
            .buttonStyle(.borderedProminent)
        }
        .alert("Terminé", isPresented: $showDoneAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Le programme a été régénéré. Revenez à l'onglet Workout ou rafraîchissez pour le voir.")
        }
    }

    private func forceSeed() {
        isForcing = true
        Task { @MainActor in
            DataController.deleteAll(context: context)
            await DataController.createDefaultProgram(context: context)
            isForcing = false
            showDoneAlert = true
        }
    }
}
