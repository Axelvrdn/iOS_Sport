//
//  ExerciseLibraryView.swift
//  Muscu
//
//  Grille type catalogue : filtres muscles en capsules (40pt), cartes 2 colonnes, fond unifié #0F1115.
//

import SwiftUI
import SwiftData

private let LibraryBgDark = Color(red: 15/255, green: 17/255, blue: 21/255)
private let LibraryCardDark = Color(red: 28/255, green: 31/255, blue: 38/255)
private let LibraryCardHeight: CGFloat = 140

struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentColor) private var accentColor
    @Environment(\.tabBarVisibilityStore) private var tabBarVisibilityStore

    @Query(sort: \ExerciseMaster.name) private var allMasters: [ExerciseMaster]
    @State private var searchText: String = ""
    @State private var selectedMuscleGroup: MuscleGroup? = nil

    /// Filtre par recherche texte puis par groupe musculaire (musclesTargeted contient le groupe sélectionné).
    private var filteredMasters: [ExerciseMaster] {
        var list = allMasters
        if !searchText.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        if let group = selectedMuscleGroup {
            list = list.filter { master in
                master.musclesTargeted.contains(group)
            }
        }
        return list
    }

    private var pageBackground: Color {
        colorScheme == .dark ? LibraryBgDark : Color(.systemGroupedBackground)
    }

    private var cardBackground: Color {
        colorScheme == .dark ? LibraryCardDark : Color.white
    }

    var body: some View {
        ZStack {
            pageBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                filterBar
                gridContent
            }
        }
        .searchable(text: $searchText, prompt: "Rechercher un exercice")
        .navigationTitle("Bibliothèque")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { tabBarVisibilityStore?.isSubPageActive = true }
        .onDisappear { tabBarVisibilityStore?.isSubPageActive = false }
    }

    // MARK: - Filtres muscles (hauteur 40pt, capsules, bordure accent si sélectionné)

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                filterChip(label: "Tous", isSelected: selectedMuscleGroup == nil) {
                    selectedMuscleGroup = nil
                }
                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    filterChip(label: muscleGroupLabel(group), isSelected: selectedMuscleGroup == group) {
                        selectedMuscleGroup = group
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(height: 40 + 24)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.05))
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(isSelected ? accentColor : Color.primary)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(Capsule().fill(isSelected ? accentColor.opacity(0.15) : Color.primary.opacity(0.06)))
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? accentColor : Color.clear, lineWidth: 0.5)
                )
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grille 2 colonnes, cartes 140pt, dégradé + badges

    @ViewBuilder
    private var gridContent: some View {
        if filteredMasters.isEmpty {
            ContentUnavailableView(
                "Aucun exercice",
                systemImage: "figure.strengthtraining.traditional",
                description: Text(searchText.isEmpty ? "Aucun exercice dans ce filtre." : "Aucun résultat pour « \(searchText) ».")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    ForEach(filteredMasters) { master in
                        NavigationLink {
                            ExerciseDetailView(master: master)
                        } label: {
                            ExerciseLibraryCard(
                                master: master,
                                cardBackground: cardBackground,
                                accentColor: accentColor,
                                colorScheme: colorScheme
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .safeAreaPadding(.bottom, 120)
        }
    }

    private func muscleGroupLabel(_ g: MuscleGroup) -> String {
        switch g {
        case .chest: return "Pectoraux"
        case .back: return "Dos"
        case .legs: return "Jambes"
        case .shoulders: return "Épaules"
        case .arms: return "Bras"
        case .core: return "Gainage"
        case .fullBody: return "Full body"
        }
    }
}

// MARK: - Carte exercice (140pt, icône centre, nom en bas ; mode clair = fond blanc + texte noir)

private struct ExerciseLibraryCard: View {
    let master: ExerciseMaster
    let cardBackground: Color
    let accentColor: Color
    let colorScheme: ColorScheme

    private var levelLabel: String {
        master.estimatedOneRM > 0 || master.musclesTargeted.count > 1 ? "Pro" : "Débutant"
    }

    private var materialLabel: String {
        master.musclesTargeted.contains(.fullBody) ? "Full body" : "Poids"
    }

    private var isDark: Bool { colorScheme == .dark }

    private var cardBorder: Color {
        isDark ? Color.clear : Color.gray.opacity(0.2)
    }

    private var textColor: Color {
        isDark ? .white : Color.primary
    }

    private var badgeBgColor: Color {
        isDark ? Color.white.opacity(0.2) : Color.primary.opacity(0.08)
    }

    private var badgeTextColor: Color {
        isDark ? .white : Color.primary
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackground)
                .overlay {
                    Image(systemName: master.visualAsset)
                        .font(.system(size: 44))
                        .foregroundStyle(accentColor.opacity(isDark ? 0.6 : 0.5))
                }
                .overlay {
                    if isDark {
                        VStack {
                            LinearGradient(
                                colors: [Color.clear, Color.black.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: LibraryCardHeight * 0.5)
                        }
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }

            HStack(spacing: 4) {
                Text(levelLabel)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                Text("·")
                    .font(.system(size: 9))
                Text(materialLabel)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(badgeTextColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(badgeBgColor))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(8)

            VStack(alignment: .leading, spacing: 2) {
                Spacer()
                Text(master.name)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(textColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if master.estimatedOneRM > 0 {
                    Text("PR \(String(format: "%.0f", master.estimatedOneRM)) kg")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(isDark ? .white.opacity(0.85) : Color.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(height: LibraryCardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: isDark ? 0 : 0.5)
        )
        .shadow(
            color: isDark ? .clear : .black.opacity(0.05),
            radius: isDark ? 0 : 6,
            x: 0,
            y: 2
        )
    }
}

#Preview("Bibliothèque") {
    NavigationStack {
        ExerciseLibraryView()
            .environment(\.accentColor, Color(red: 208/255, green: 253/255, blue: 62/255))
    }
    .modelContainer(for: [ExerciseMaster.self], inMemory: true)
}
