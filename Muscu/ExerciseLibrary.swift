//
//  ExerciseLibrary.swift
//  Muscu
//
//  Rôle : Transforme la bibliothèque textuelle d’exercices (pectoraux, dos, épaules, bras, jambes, abdos)
//  en objets SwiftData persistants (ExerciseMaster) avec catégorie, description et groupes musculaires.
//

import Foundation
import SwiftData

// MARK: - Catégories haut niveau

enum ExerciseCategory: String, Codable, CaseIterable {
    case chest = "Pectoraux"
    case back = "Dos"
    case shoulders = "Épaules"
    case biceps = "Biceps"
    case triceps = "Triceps"
    case legsGlutes = "Jambes & Fessiers"
    case core = "Abdos & Gainage"
}

private struct ExerciseLibraryEntry {
    let name: String
    let category: ExerciseCategory
    let description: String
}

// MARK: - API principale

/// Insère la bibliothèque exhaustive d’exercices généraux dans SwiftData (ExerciseMaster),
/// en évitant les doublons (clé = nom).
@MainActor
func createExtendedExerciseLibrary(context: ModelContext) async {
    let entries = exerciseLibraryEntries()
    let existingMasters = (try? context.fetch(FetchDescriptor<ExerciseMaster>())) ?? []
    var existingNames = Set(existingMasters.map { $0.name })

    for entry in entries {
        guard !existingNames.contains(entry.name) else { continue }

        let master = ExerciseMaster(
            name: entry.name,
            exerciseDescription: entry.description,
            musclesTargetedString: musclesForCategory(entry.category)
        )
        context.insert(master)
        existingNames.insert(entry.name)
    }

    do {
        try context.save()
        print("[ExerciseLibrary] \(entries.count) exercices traités (sans doublons).")
    } catch {
        print("[ExerciseLibrary] Erreur de sauvegarde : \(error)")
    }
}

// MARK: - Mapping catégories → groupes musculaires

private func musclesForCategory(_ category: ExerciseCategory) -> String {
    switch category {
    case .chest:
        return "chest"
    case .back:
        return "back"
    case .shoulders:
        return "shoulders"
    case .biceps:
        return "arms"
    case .triceps:
        return "arms"
    case .legsGlutes:
        return "legs"
    case .core:
        return "core"
    }
}

// MARK: - Données brutes (texte → entrées)

private func exerciseLibraryEntries() -> [ExerciseLibraryEntry] {
    var items: [ExerciseLibraryEntry] = []

    // 1. PECTORAUX
    items.append(contentsOf: [
        ExerciseLibraryEntry(
            name: "Développé couché barre",
            category: .chest,
            description: "L'exercice de référence pour la masse globale des pectoraux, avec un focus sur la portion médiane."
        ),
        ExerciseLibraryEntry(
            name: "Développé couché haltères",
            category: .chest,
            description: "Permet une plus grande amplitude de mouvement et un travail stabilisateur accru pour chaque côté."
        ),
        ExerciseLibraryEntry(
            name: "Développé incliné barre",
            category: .chest,
            description: "Met l'accent sur la portion haute des pectoraux (clavi-pectorale) grâce à l'inclinaison du banc."
        ),
        ExerciseLibraryEntry(
            name: "Développé incliné haltères",
            category: .chest,
            description: "Idéal pour corriger les asymétries et cibler le haut du torse avec une amplitude importante."
        ),
        ExerciseLibraryEntry(
            name: "Développé décliné",
            category: .chest,
            description: "Met davantage l'accent sur la partie inférieure des pectoraux et permet souvent de pousser plus lourd."
        ),
        ExerciseLibraryEntry(
            name: "Écartés couchés (Dumbbell Flyes)",
            category: .chest,
            description: "Exercice d'isolation pour étirer les fibres pectorales et accentuer la congestion."
        ),
        ExerciseLibraryEntry(
            name: "Écartés à la poulie vis-à-vis",
            category: .chest,
            description: "Offre une tension continue sur les pectoraux, idéal en finition de séance."
        ),
        ExerciseLibraryEntry(
            name: "Dips prise large",
            category: .chest,
            description: "Travail puissant du bas des pectoraux et de l'épaisseur du buste, au poids du corps ou lesté."
        ),
        ExerciseLibraryEntry(
            name: "Pompes classiques",
            category: .chest,
            description: "Exercice de base au poids du corps pour la force générale du haut du corps."
        ),
        ExerciseLibraryEntry(
            name: "Pompes diamant",
            category: .chest,
            description: "Variante serrée qui sollicite l'intérieur des pectoraux tout en chargeant fortement les triceps."
        ),
        ExerciseLibraryEntry(
            name: "Pompes pieds surélevés",
            category: .chest,
            description: "Variante où les pieds sont surélevés pour augmenter le travail du haut des pectoraux."
        ),
        ExerciseLibraryEntry(
            name: "Pull-over",
            category: .chest,
            description: "Ouvre la cage thoracique et recrute le grand dentelé ainsi que les pectoraux."
        ),
        ExerciseLibraryEntry(
            name: "Machine Chest Press",
            category: .chest,
            description: "Presse poitrine guidée, sécurisante pour pousser lourd ou aller à l'échec."
        ),
        ExerciseLibraryEntry(
            name: "Pec Deck (Butterfly)",
            category: .chest,
            description: "Machine d'isolation pour travailler la ligne médiane et les stries des pectoraux."
        ),
        ExerciseLibraryEntry(
            name: "Écartés poulie basse",
            category: .chest,
            description: "Mouvement ascendant depuis le bas pour cibler la partie haute interne des pectoraux."
        )
    ])

    // 2. DOS
    items.append(contentsOf: [
        ExerciseLibraryEntry(
            name: "Soulevé de terre",
            category: .back,
            description: "Exercice complet pour la chaîne postérieure, développant force et masse du dos et des jambes."
        ),
        ExerciseLibraryEntry(
            name: "Tractions prise large",
            category: .back,
            description: "Met l'accent sur le grand dorsal et la largeur en V du dos."
        ),
        ExerciseLibraryEntry(
            name: "Tractions prise neutre ou serrée",
            category: .back,
            description: "Accentue le travail des biceps et du bas des dorsaux avec une trajectoire plus verticale."
        ),
        ExerciseLibraryEntry(
            name: "Tirage vertical poitrine",
            category: .back,
            description: "Alternative aux tractions permettant de contrôler précisément la charge et la trajectoire."
        ),
        ExerciseLibraryEntry(
            name: "Rowing barre buste penché",
            category: .back,
            description: "Puissant exercice pour l'épaisseur du milieu du dos et la stabilité lombaire."
        ),
        ExerciseLibraryEntry(
            name: "Rowing haltère unilatéral",
            category: .back,
            description: "Permet de corriger les déséquilibres en se concentrant sur un côté à la fois."
        ),
        ExerciseLibraryEntry(
            name: "Rowing T-Bar",
            category: .back,
            description: "Variante de rowing avec prise serrée axée sur l'épaisseur centrale du dos."
        ),
        ExerciseLibraryEntry(
            name: "Tirage horizontal poulie basse",
            category: .back,
            description: "Travail ciblant les trapèzes et les rhomboïdes avec une trajectoire horizontale."
        ),
        ExerciseLibraryEntry(
            name: "Tirage poulie haute bras tendus",
            category: .back,
            description: "Exercice d'isolation du grand dorsal sans forte intervention des biceps."
        ),
        ExerciseLibraryEntry(
            name: "Rack Pulls",
            category: .back,
            description: "Soulevé de terre partiel depuis des rehausses pour renforcer lombaires et trapèzes."
        ),
        ExerciseLibraryEntry(
            name: "Extensions lombaires",
            category: .back,
            description: "Renforcement du bas du dos sur banc à 45° ou banc horizontal."
        ),
        ExerciseLibraryEntry(
            name: "Shrugs barre",
            category: .back,
            description: "Haussements d'épaules lourds pour développer la masse des trapèzes supérieurs."
        ),
        ExerciseLibraryEntry(
            name: "Shrugs haltères",
            category: .back,
            description: "Variante aux haltères offrant une plus grande liberté de mouvement pour les trapèzes."
        ),
        ExerciseLibraryEntry(
            name: "Rowing à la machine convergente",
            category: .back,
            description: "Rowing guidé permettant un travail contrôlé de l'ensemble du dos."
        ),
        ExerciseLibraryEntry(
            name: "Face Pull",
            category: .back,
            description: "Crucial pour la santé de l'épaule et le renforcement de l'arrière d'épaule et du haut du dos."
        )
    ])

    // 3. ÉPAULES
    items.append(contentsOf: [
        ExerciseLibraryEntry(
            name: "Développé militaire",
            category: .shoulders,
            description: "Presse au-dessus de la tête développant la force globale des épaules et du haut du corps."
        ),
        ExerciseLibraryEntry(
            name: "Développé haltères assis",
            category: .shoulders,
            description: "Presse épaules assise avec haltères, plus douce pour les articulations et plus stable."
        ),
        ExerciseLibraryEntry(
            name: "Élévations latérales haltères",
            category: .shoulders,
            description: "Exercice clé pour élargir les épaules en ciblant le faisceau latéral."
        ),
        ExerciseLibraryEntry(
            name: "Élévations latérales poulie",
            category: .shoulders,
            description: "Version à la poulie avec tension constante sur le faisceau moyen."
        ),
        ExerciseLibraryEntry(
            name: "Arnold Press",
            category: .shoulders,
            description: "Presse épaules avec rotation, sollicitant le faisceau antérieur et latéral."
        ),
        ExerciseLibraryEntry(
            name: "Élévations frontales",
            category: .shoulders,
            description: "Cible spécifiquement la partie avant de l'épaule avec barre ou haltères."
        ),
        ExerciseLibraryEntry(
            name: "Oiseau haltères",
            category: .shoulders,
            description: "Exercice pour l'arrière d'épaule, souvent négligé mais essentiel pour l'équilibre."
        ),
        ExerciseLibraryEntry(
            name: "Oiseau poulie haute",
            category: .shoulders,
            description: "Variante à la poulie pour un travail de finition de l'arrière d'épaule."
        ),
        ExerciseLibraryEntry(
            name: "Tirage menton",
            category: .shoulders,
            description: "Tirage vertical pour les trapèzes et le haut des épaules (attention à la morphologie)."
        ),
        ExerciseLibraryEntry(
            name: "Développé Smith Machine",
            category: .shoulders,
            description: "Presse épaules guidée permettant de se concentrer sur la poussée sans stabilisation."
        ),
        ExerciseLibraryEntry(
            name: "L-Fly",
            category: .shoulders,
            description: "Rotations externes pour renforcer la coiffe des rotateurs en prévention des blessures."
        ),
        ExerciseLibraryEntry(
            name: "Landmine Press unilatéral",
            category: .shoulders,
            description: "Presse unilatérale en landmine, excellente pour la stabilité et le faisceau antérieur."
        ),
        ExerciseLibraryEntry(
            name: "Machine Shoulder Press",
            category: .shoulders,
            description: "Presse épaules en machine, idéale pour les séries longues d'hypertrophie."
        ),
        ExerciseLibraryEntry(
            name: "Élévations latérales machine",
            category: .shoulders,
            description: "Isolation parfaite du faisceau moyen sans élan possible."
        )
    ])

    // 4. BICEPS
    items.append(contentsOf: [
        ExerciseLibraryEntry(
            name: "Curl barre droite",
            category: .biceps,
            description: "Le classique du biceps pour développer la masse globale avec une prise en supination."
        ),
        ExerciseLibraryEntry(
            name: "Curl barre EZ",
            category: .biceps,
            description: "Variante plus confortable pour les poignets grâce à la barre coudée."
        ),
        ExerciseLibraryEntry(
            name: "Curl haltères supination",
            category: .biceps,
            description: "Permet la rotation du poignet pour une contraction maximale du biceps."
        ),
        ExerciseLibraryEntry(
            name: "Curl marteau",
            category: .biceps,
            description: "Cible le brachial et le long supinateur pour donner de l'épaisseur au bras."
        ),
        ExerciseLibraryEntry(
            name: "Curl pupitre",
            category: .biceps,
            description: "Curl au pupitre (Preacher) pour une isolation totale et éviter de tricher avec le buste."
        ),
        ExerciseLibraryEntry(
            name: "Curl incliné",
            category: .biceps,
            description: "Curl sur banc incliné offrant un étirement maximal du long chef du biceps."
        ),
        ExerciseLibraryEntry(
            name: "Curl concentration",
            category: .biceps,
            description: "Curl assis avec le coude calé contre la cuisse pour accentuer le \"pic\" du biceps."
        ),
        ExerciseLibraryEntry(
            name: "Curl poulie basse",
            category: .biceps,
            description: "Curl à la poulie (barre ou corde) avec tension continue sur toute l'amplitude."
        ),
        ExerciseLibraryEntry(
            name: "Curl inversé",
            category: .biceps,
            description: "Curl en prise pronation ciblant davantage le dessus de l'avant-bras et le brachial."
        ),
        ExerciseLibraryEntry(
            name: "Spider Curl",
            category: .biceps,
            description: "Curl buste contre banc incliné avec tension maximale en haut du mouvement."
        ),
        ExerciseLibraryEntry(
            name: "Curl 21",
            category: .biceps,
            description: "Technique d'intensité : 7 reps bas, 7 reps haut, 7 reps complètes pour brûler le muscle."
        ),
        ExerciseLibraryEntry(
            name: "Drag Curl",
            category: .biceps,
            description: "Variante où la barre glisse le long du corps pour limiter l'intervention des épaules."
        ),
        ExerciseLibraryEntry(
            name: "Zottman Curl",
            category: .biceps,
            description: "Montée en supination, rotation, puis descente en prise inversée pour l'avant-bras et le biceps."
        ),
        ExerciseLibraryEntry(
            name: "Curl poulie haute double biceps",
            category: .biceps,
            description: "Curl aux câbles bras écartés pour travailler la contraction et la pose double biceps."
        )
    ])

    // 5. TRICEPS
    items.append(contentsOf: [
        ExerciseLibraryEntry(
            name: "Barre au front",
            category: .triceps,
            description: "Skullcrushers, un pilier pour la masse globale des triceps en position couchée."
        ),
        ExerciseLibraryEntry(
            name: "Extensions poulie haute corde",
            category: .triceps,
            description: "Excellente contraction du chef latéral du triceps grâce à l'écartement en fin de mouvement."
        ),
        ExerciseLibraryEntry(
            name: "Extensions poulie haute barre",
            category: .triceps,
            description: "Variante à la barre droite ou en V permettant de mettre plus lourd sur les triceps."
        ),
        ExerciseLibraryEntry(
            name: "Dips barres parallèles",
            category: .triceps,
            description: "Exercice de puissance majeur pour les triceps et la ceinture scapulaire."
        ),
        ExerciseLibraryEntry(
            name: "Développé couché prise serrée",
            category: .triceps,
            description: "Presse horizontale serrée mettant l'accent sur la force des triceps."
        ),
        ExerciseLibraryEntry(
            name: "Extensions haltère au-dessus de la tête",
            category: .triceps,
            description: "Extension triceps au-dessus de la tête pour cibler fortement le long chef."
        ),
        ExerciseLibraryEntry(
            name: "Extensions poulie derrière la tête",
            category: .triceps,
            description: "Version à la poulie offrant un étirement constant du long chef du triceps."
        ),
        ExerciseLibraryEntry(
            name: "Kickback haltère",
            category: .triceps,
            description: "Exercice d'isolation de finition, demandant un bon contrôle pour éviter l'élan."
        ),
        ExerciseLibraryEntry(
            name: "Kickback poulie",
            category: .triceps,
            description: "Kickback à la poulie avec un meilleur profil de résistance que l'haltère."
        ),
        ExerciseLibraryEntry(
            name: "Dips entre deux bancs",
            category: .triceps,
            description: "Variante accessible partout pour cibler les triceps au poids du corps."
        ),
        ExerciseLibraryEntry(
            name: "Pompes mains serrées",
            category: .triceps,
            description: "Pompes en prise rapprochée mettant fortement en jeu les triceps."
        ),
        ExerciseLibraryEntry(
            name: "Tate Press",
            category: .triceps,
            description: "Variante d'extension triceps aux haltères ciblant le chef latéral."
        )
    ])

    // 6. JAMBES & FESSIERS
    items.append(contentsOf: [
        ExerciseLibraryEntry(
            name: "Squat barre haute",
            category: .legsGlutes,
            description: "Squat high bar, référence pour développer les quadriceps et le gainage."
        ),
        ExerciseLibraryEntry(
            name: "Squat barre basse",
            category: .legsGlutes,
            description: "Squat low bar, permettant souvent plus de charge en sollicitant davantage la chaîne postérieure."
        ),
        ExerciseLibraryEntry(
            name: "Front Squat",
            category: .legsGlutes,
            description: "Squat avant avec barre sur les épaules, très exigeant pour les quadriceps et le tronc."
        ),
        ExerciseLibraryEntry(
            name: "Presse à cuisses",
            category: .legsGlutes,
            description: "Machine idéale pour accumuler du volume sur les cuisses sans surcharger le dos."
        ),
        ExerciseLibraryEntry(
            name: "Fentes bulgares",
            category: .legsGlutes,
            description: "Exercice unilatéral redoutable pour les quadriceps, les fessiers et l'équilibre."
        ),
        ExerciseLibraryEntry(
            name: "Leg Extension",
            category: .legsGlutes,
            description: "Extension de jambes en machine pour isoler le quadriceps."
        ),
        ExerciseLibraryEntry(
            name: "Leg Curl",
            category: .legsGlutes,
            description: "Leg curl assis ou couché pour cibler les ischios-jambiers."
        ),
        ExerciseLibraryEntry(
            name: "Soulevé de terre jambes tendues",
            category: .legsGlutes,
            description: "Énorme étirement des ischios-jambiers et travail de la chaîne postérieure."
        ),
        ExerciseLibraryEntry(
            name: "Soulevé de terre roumain",
            category: .legsGlutes,
            description: "Variante du soulevé de terre centrée sur les fessiers et ischios avec dos gainé."
        ),
        ExerciseLibraryEntry(
            name: "Hip Thrust",
            category: .legsGlutes,
            description: "Exercice numéro un pour l'hypertrophie des fessiers, en charge horizontale."
        ),
        ExerciseLibraryEntry(
            name: "Hack Squat",
            category: .legsGlutes,
            description: "Squat en machine guidée pour cibler intensément les cuisses en toute stabilité."
        ),
        ExerciseLibraryEntry(
            name: "Goblet Squat",
            category: .legsGlutes,
            description: "Squat avec haltère tenu devant, excellent pour apprendre le mouvement ou s'échauffer."
        ),
        ExerciseLibraryEntry(
            name: "Fentes marchées",
            category: .legsGlutes,
            description: "Fentes en déplacement sollicitant jambes, fessiers et cardio."
        ),
        ExerciseLibraryEntry(
            name: "Adducteurs machine",
            category: .legsGlutes,
            description: "Machine pour renforcer l'intérieur des cuisses (adducteurs)."
        ),
        ExerciseLibraryEntry(
            name: "Abducteurs machine",
            category: .legsGlutes,
            description: "Machine pour cibler le moyen fessier et le galbe latéral de la hanche."
        ),
        ExerciseLibraryEntry(
            name: "Extensions mollets debout",
            category: .legsGlutes,
            description: "Standing calf raise ciblant principalement les jumeaux."
        ),
        ExerciseLibraryEntry(
            name: "Extensions mollets assis",
            category: .legsGlutes,
            description: "Assis, cible davantage le soléaire situé sous le mollet."
        ),
        ExerciseLibraryEntry(
            name: "Presse à mollets",
            category: .legsGlutes,
            description: "Extensions de mollets à la presse pour charger lourd en toute sécurité."
        )
    ])

    // 7. ABDOMINAUX & GAINAGE
    items.append(contentsOf: [
        ExerciseLibraryEntry(
            name: "Gainage planche",
            category: .core,
            description: "Exercice isométrique de base pour la stabilité profonde de la sangle abdominale."
        ),
        ExerciseLibraryEntry(
            name: "Crunch au sol",
            category: .core,
            description: "Flexion du buste au sol pour cibler le grand droit de l'abdomen."
        ),
        ExerciseLibraryEntry(
            name: "Crunch poulie haute",
            category: .core,
            description: "Crunch lesté à la poulie pour épaissir les abdominaux."
        ),
        ExerciseLibraryEntry(
            name: "Levée de jambes suspendu",
            category: .core,
            description: "Relevés de jambes en suspension, excellents pour le bas des abdos."
        ),
        ExerciseLibraryEntry(
            name: "Roulette à abdos",
            category: .core,
            description: "Ab Wheel, très exigeant pour l'ensemble de la sangle abdominale et le gainage."
        ),
        ExerciseLibraryEntry(
            name: "Russian Twist",
            category: .core,
            description: "Rotation du buste pour travailler les obliques avec ou sans charge."
        ),
        ExerciseLibraryEntry(
            name: "Mountain Climbers",
            category: .core,
            description: "Exercice dynamique combinant cardio et gainage en position de planche."
        ),
        ExerciseLibraryEntry(
            name: "Reverse Crunch",
            category: .core,
            description: "Enroulement du bassin vers la poitrine pour cibler le bas du grand droit."
        ),
        ExerciseLibraryEntry(
            name: "Side Plank",
            category: .core,
            description: "Gainage latéral pour les obliques et le carré des lombes."
        ),
        ExerciseLibraryEntry(
            name: "V-Ups",
            category: .core,
            description: "Mouvement explosif en V sollicitant fortement toute la sangle abdominale."
        ),
        ExerciseLibraryEntry(
            name: "Bicycle Crunch",
            category: .core,
            description: "Crunch avec mouvement alternatif des jambes pour une sollicitation complète des abdos."
        ),
        ExerciseLibraryEntry(
            name: "Woodchopper poulie",
            category: .core,
            description: "Mouvement de rotation à la poulie de haut en bas pour renforcer les obliques."
        )
    ])

    return items
}

