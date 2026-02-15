//
//  SettingsView.swift
//  Muscu
//
//  Paramètres : liste structurée avec Profil, Préférences, Informations.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profileSummaryTitle)
                                    .font(.headline)
                                Text(profileSummarySubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Profil")
                }

                Section {
                    NavigationLink {
                        AICoachSettingsView()
                    } label: {
                        Label("AI Coach", systemImage: "brain.head.profile")
                    }
                    NavigationLink {
                        DisplaySettingsView()
                    } label: {
                        Label("Affichage", systemImage: "paintbrush")
                    }
                    NavigationLink {
                        LanguageRegionView()
                    } label: {
                        Label("Langue et Région", systemImage: "globe")
                    }
                } header: {
                    Text("Préférences & Coaching")
                }

                Section {
                    NavigationLink {
                        LegalPrivacyView()
                    } label: {
                        Label("Mentions Légales & Confidentialité", systemImage: "doc.text")
                    }
                    NavigationLink {
                        AboutAppView()
                    } label: {
                        Label("À propos de l'application", systemImage: "info.circle")
                    }
                } header: {
                    Text("Informations")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Paramètres")
            .background(Color(.systemGroupedBackground))
        }
    }

    private var profileSummaryTitle: String {
        guard profile != nil else { return "Mon Profil" }
        return "Mon Profil"
    }

    private var profileSummarySubtitle: String {
        guard let p = profile else { return "Compléter le profil" }
        return "\(p.age) ans • \(Int(p.weight)) kg • \(p.physiqueGoal.displayName)"
    }
}

// MARK: - AI Coach (rigueur, personnalité)

struct AICoachSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @State private var strictnessLevel: Double = 0.5

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Niveau de rigueur du coach")
                        .font(.subheadline.bold())
                    Slider(value: $strictnessLevel, in: 0...1, step: 0.05)
                    HStack {
                        Text("Cool")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Très strict")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Personnalité")
            } footer: {
                Text("Plus le niveau est élevé, plus le coach sera exigeant sur la régularité et la forme.")
            }

            Section {
                Text("Personnalité : \(strictnessLevel < 0.4 ? "Accompagnant" : (strictnessLevel < 0.7 ? "Équilibré" : "Exigeant"))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("AI Coach")
        .onAppear { strictnessLevel = profile?.strictnessLevel ?? 0.5 }
        .onChange(of: strictnessLevel) { _, newValue in
            profile?.strictnessLevel = newValue
            try? context.save()
        }
    }
}

// MARK: - Affichage (mode sombre/clair, unités)

struct DisplaySettingsView: View {
    @AppStorage("useDarkMode") private var useDarkMode: Bool = false
    @AppStorage("useMetricUnits") private var useMetricUnits: Bool = true
    @AppStorage("healthKitAutoSync") private var healthKitAutoSync: Bool = true

    var body: some View {
        Form {
            Section {
                Toggle("Mode sombre", isOn: $useDarkMode)
            } header: {
                Text("Apparence")
            }

            Section {
                Toggle("Synchroniser avec Santé (âge, poids)", isOn: $healthKitAutoSync)
            } header: {
                Text("Santé (Apple Santé)")
            } footer: {
                Text("Remplit automatiquement le profil avec la date de naissance (âge) et le dernier poids depuis l’app Santé.")
            }

            Section {
                Toggle("Unités métriques (kg)", isOn: $useMetricUnits)
            } header: {
                Text("Unités")
            } footer: {
                Text("Désactiver pour afficher les poids en livres (lbs).")
            }
        }
        .navigationTitle("Affichage")
    }
}

// MARK: - Langue et Région

struct LanguageRegionView: View {
    var body: some View {
        Form {
            Section {
                Text("La langue de l'application suit celle de ton appareil.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Langue")
            }

            Section {
                Text("Région : \(Locale.current.region?.identifier ?? "—")")
                    .font(.subheadline)
            } header: {
                Text("Région")
            }
        }
        .navigationTitle("Langue et Région")
    }
}

// MARK: - Mentions Légales & Confidentialité

struct LegalPrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Mentions légales")
                    .font(.headline)
                Text("Muscu est une application de suivi d'entraînement. Les données sont stockées localement sur ton appareil.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Confidentialité")
                    .font(.headline)
                Text("Nous ne collectons pas de données personnelles à des fins commerciales. Les données de santé (HealthKit) restent sur ton appareil et ne sont partagées qu'avec ton consentement.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Mentions Légales & Confidentialité")
    }
}

// MARK: - À propos (version)

struct AboutAppView: View {
    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    private var buildNumber: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("\(appVersion) (\(buildNumber))")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("Muscu — Suivi d'entraînement et programmes personnalisables.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("À propos")
    }
}
