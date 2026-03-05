//
//  ExerciseDetailView.swift
//  Muscu
//
//  Fiche exercice DA "Elite Architect" : média 16:9, stats sleek, graphique glow, bouton d'action.
//

import SwiftUI
import SwiftData
import Charts

private let DetailBgDark = Color(red: 15/255, green: 17/255, blue: 21/255)
private let DetailCardDark = Color(red: 28/255, green: 31/255, blue: 38/255)
private let MediaCornerRadius: CGFloat = 24
private let MediaAspectRatio: CGFloat = 16 / 9

struct ExerciseDetailView: View {
    let master: ExerciseMaster
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentColor) private var accentColor
    @Environment(\.textOnAccentColor) private var textOnAccentColor

    @Query(sort: \ExerciseSetResult.date) private var allSetResults: [ExerciseSetResult]
    @Query private var allRecipes: [SessionRecipe]

    @State private var showAddToSessionSheet: Bool = false
    @State private var recipeToConfigure: RecipeSelection?

    private var setResults: [ExerciseSetResult] {
        let id = master.persistentModelID
        return allSetResults.filter { $0.exercise?.persistentModelID == id }.sorted { $0.date < $1.date }
    }

    private var personalRecord1RM: Double { master.estimatedOneRM }
    private var totalVolume: Double {
        setResults.reduce(0) { $0 + Double($1.reps) * $1.weight }
    }
    private var bestEstimated1RMInHistory: Double? {
        setResults.map(\.estimatedOneRM).filter { $0 > 0 }.max()
    }

    private var pageBackground: Color {
        colorScheme == .dark ? DetailBgDark : Color.white
    }

    private var cardBackground: Color {
        colorScheme == .dark ? DetailCardDark : Color.white
    }

    private var cardBorder: Color {
        colorScheme == .dark ? Color.clear : Color.gray.opacity(0.2)
    }

    var body: some View {
        ZStack {
            pageBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    mediaSection
                    statsSection
                    if !setResults.isEmpty { chartSection }
                }
                .padding(16)
                .padding(.bottom, 100)
            }

            VStack {
                Spacer()
                addToSessionButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
        }
        .navigationTitle(master.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showAddToSessionSheet) {
            addToSessionSheet
        }
        .sheet(item: $recipeToConfigure) { selection in
            ExerciseConfigSheet(master: master, sessionRecipe: selection.recipe)
        }
    }

    // MARK: - Section Média (16:9, coins 24pt, bordure accent 10%, glow)

    private var mediaSection: some View {
        Group {
            if let url = master.videoUrl, !url.isEmpty {
                YouTubeEmbedView(videoUrl: url)
                    .aspectRatio(MediaAspectRatio, contentMode: .fit)
            } else {
                Image(systemName: master.visualAsset)
                    .font(.system(size: 64))
                    .foregroundStyle(accentColor.opacity(colorScheme == .dark ? 0.6 : 0.5))
                    .frame(maxWidth: .infinity)
                    .aspectRatio(MediaAspectRatio, contentMode: .fill)
                    .background(cardBackground)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MediaCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MediaCornerRadius, style: .continuous)
                .strokeBorder(accentColor.opacity(0.1), lineWidth: 0.5)
        )
        .glow(color: accentColor, opacity: colorScheme == .dark ? 0.35 : 0.15, radius: 20, y: 8)
    }

    // MARK: - Stats clés (2 colonnes, chiffres monospaced accent)

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stats clés")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                statCard(title: "Record (1RM est.)", value: personalRecord1RM > 0 ? String(format: "%.1f kg", personalRecord1RM) : "—")
                statCard(title: "Volume total", value: totalVolume > 0 ? "\(Int(totalVolume)) kg" : "—")
            }
            if let best = bestEstimated1RMInHistory, best > 0 {
                Text("Meilleur 1RM en séance : \(String(format: "%.1f", best)) kg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(accentColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 0.5)
        )
        .shadow(
            color: colorScheme == .light ? .black.opacity(0.05) : .clear,
            radius: colorScheme == .light ? 6 : 0,
            x: 0,
            y: 2
        )
    }

    // MARK: - Graphique progression (courbe lissée, dégradé sous la courbe, glow, pas de grille)

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progression (poids max par séance)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Chart {
                ForEach(setResults.filter { $0.estimatedOneRM > 0 }, id: \.persistentModelID) { result in
                    AreaMark(
                        x: .value("Date", result.date),
                        y: .value("1RM est.", result.estimatedOneRM)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accentColor.opacity(0.4), accentColor.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("Date", result.date),
                        y: .value("1RM est.", result.estimatedOneRM)
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(accentColor)
                    PointMark(
                        x: .value("Date", result.date),
                        y: .value("1RM est.", result.estimatedOneRM)
                    )
                    .foregroundStyle(accentColor)
                    .symbolSize(30)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0))
                    AxisValueLabel()
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0))
                    AxisValueLabel()
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxisLabel("1RM estimé (kg)")
            .frame(height: 220)
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 0.5)
        )
        .shadow(
            color: colorScheme == .light ? .black.opacity(0.05) : .clear,
            radius: colorScheme == .light ? 6 : 0,
            x: 0,
            y: 2
        )
        .glow(color: accentColor, opacity: colorScheme == .dark ? 0.25 : 0.08, radius: 12, y: 4)
    }

    // MARK: - Bouton d'action principal

    private var addToSessionButton: some View {
        Button {
            showAddToSessionSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                Text("Ajouter à ma séance")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(textOnAccentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var addToSessionSheet: some View {
        NavigationStack {
            List {
                ForEach(allRecipes, id: \.persistentModelID) { recipe in
                    Button {
                        recipeToConfigure = RecipeSelection(recipe: recipe)
                        showAddToSessionSheet = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recipe.name)
                                    .font(.headline)
                                if let programName = recipe.day?.week?.program?.name {
                                    Text(programName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .navigationTitle("Choisir une séance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { showAddToSessionSheet = false }
                }
            }
        }
    }
}

/// Wrapper Identifiable pour présenter la sheet de configuration (évite d'étendre SessionRecipe).
private struct RecipeSelection: Identifiable {
    let recipe: SessionRecipe
    var id: PersistentIdentifier { recipe.persistentModelID }
}

#Preview {
    NavigationStack {
        ExerciseDetailView(master: ExerciseMaster(name: "Développé couché", visualAsset: "figure.strengthtraining.traditional", estimatedOneRM: 80))
    }
    .environment(\.accentColor, Color(red: 208/255, green: 253/255, blue: 62/255))
    .modelContainer(for: [ExerciseMaster.self, ExerciseSetResult.self, SessionRecipe.self], inMemory: true)
}
