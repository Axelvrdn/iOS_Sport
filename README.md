# Elite Architect : AI Coach

**L'IA de haute performance, locale et privée, pour les athlètes exigeants.**

Muscu est une application iOS pensée pour les pratiquants qui veulent un coach intelligent sans compromettre leurs données. L’IA tourne entièrement sur l’appareil : analyse des PRs, gestion des blessures et du volume en temps réel, avec des commandes actionnables en un tap. Architecture moderne, stack 2026, expérience premium.

---

## Stack Technique (Modernisation 2026)

| Composant | Choix |
|-----------|--------|
| **Plateforme** | iOS 17.0+ — *Architecture Formule 1* |
| **UI & Réactivité** | **Observation** — optimisation du rendu SwiftUI, état minimal et réactif |
| **Persistance** | **SwiftData** — modèles unifiés, migrations maîtrisées |
| **IA Locale** | **MLX-Swift** & **Mistral 7B (4-bit)** — inférence sur GPU, zéro cloud |
| **Retour tactile** | Moteur haptique haute fréquence (20 Hz) — immersion pendant le typewriter du coach |

- **Observation** : `@Observable` sur les ViewModels et managers (AICoachViewModel, WorkoutManager, AIModelDownloader, etc.) pour des mises à jour ciblées et des interfaces fluides.
- **SwiftData** : `UserProfile`, `WorkoutProgram`, `TrainingProgram`, `SessionRecipe`, etc. — un seul `ModelContainer` à l’entrée de l’app.
- **MLX** : `mlx-swift` + `mlx-swift-lm` ; modèle `mlx-community/Mistral-7B-Instruct-v0.3-4bit-mlx` chargé depuis `Application Support/MistralModel`.
- **Haptique** : dans le chat coach, retour tactile limité à 20 impulsions/s (intervalle ≥ 0,05 s) sur les espaces pour accompagner la lecture sans saturer l’API.

---

## Fonctionnalités Clés

### AI Coach Contextuel

- Analyse des **PRs**, des **blessures** et du **volume de travail** en temps réel.
- Contexte injecté depuis SwiftData (programme actif, séances, historique) pour des réponses personnalisées.
- Ton « Elite » : motivant, concis, orienté performance et récupération.
- Fallback automatique vers un moteur de règles si le modèle local n’est pas disponible ou dépasse 5 s.

### Action Parser `[ACTION: ...]`

- Système de **commandes machine-readable** en fin de message :  
  `[ACTION: DELOAD]`, `[ACTION: UPDATE_WEIGHT, VALUE: +2.5]`, etc.
- **Click to Apply** : une action suggérée par message ; l’utilisateur applique en un tap (via `CoachProtocolApplier` : Deload, Full Rest, blessure par zone).
- Parsing par regex dédiée ; le flag est retiré du texte affiché pour garder une réponse lisible.

### Master Switch & Hardware Check

- **Master Switch** : activation de l’IA locale uniquement si l’utilisateur le souhaite (`useLocalAIModel`).
- **Hardware Check** : l’IA locale n’est proposée que sur appareils **≥ 8 Go RAM** (classe iPhone 15 Pro / M1). Vérification via `ProcessInfo.physicalMemory` (seuil 6 Go rapportés pour couvrir les devices 8 Go).
- Message clair si l’appareil est sous la barre : *« L’IA locale nécessite un appareil avec au moins 8 Go de RAM… »*.

---

## Feuille de Route (Futur)

- **Système de Badges Élite** — Attribution automatique de badges (ex. « Sagesse » pour deload accepté, « Force » pour nouveau PR détecté par l’IA).
- **Mode Hands-Free (Voix)** — Synthèse vocale intelligente pour utiliser le coach sans toucher l’écran pendant les séries.
- **Analyse Biomécanique Avancée** — Intégration de modèles locaux pour prédire la fatigue nerveuse et adapter les charges.

---

## Installation & Setup

### Prérequis

- Xcode 15+ (recommandé 16+)
- macOS Sonoma ou plus récent pour développer
- Appareil ou simulateur **iOS 17.0+**
- Pour l’IA locale : appareil physique avec **≥ 8 Go RAM** (iPhone 15 Pro, M1, ou supérieur)

### Dépendances (Swift Package Manager)

Les dépendances MLX et Hugging Face sont déjà déclarées dans le projet. À l’ouverture du projet dans Xcode, Xcode résout automatiquement :

- **mlx-swift** — [github.com/ml-explore/mlx-swift](https://github.com/ml-explore/mlx-swift) (MLX core)
- **mlx-swift-lm** — [github.com/ml-explore/mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) (chargement de modèles LLM)
- **swift-transformers** — tokenizers / config (Hugging Face)
- **swift-jinja** — templates (dépendance transitive)

Si les paquets ne se résolvent pas :

1. **File → Packages → Reset Package Caches**
2. **File → Packages → Resolve Package Versions**

Aucune clé API n’est requise : l’inférence est 100 % locale.

### Téléchargement du modèle (IA locale)

Le modèle **Mistral 7B Instruct v0.3 (4-bit MLX)** est hébergé sur Hugging Face. Au premier lancement avec « IA locale » activée, l’app propose le téléchargement automatique depuis :

- **Repo** : `mlx-community/Mistral-7B-Instruct-v0.3-4bit-mlx`
- **Fichiers** : `config.json`, `tokenizer_config.json`, `tokenizer.json`, `model.safetensors`
- **Volume** : environ **4,5 Go** (principalement `model.safetensors`)

Les fichiers sont stockés dans `Application Support/MistralModel`. Une connexion Wi‑Fi stable est recommandée ; la progression et la vitesse de téléchargement sont affichées dans l’écran dédié (`AIModelDownloadView` / `AIModelDownloader`).

Pour forcer un nouveau téléchargement (ex. après corruption) : supprimer le dossier `MistralModel` dans Application Support ou utiliser la logique de nettoyage prévue dans `AIModelDownloader.clearModelFolder()`.

### Build & Run

1. Cloner le dépôt.
2. Ouvrir `Muscu.xcodeproj` dans Xcode.
3. Sélectionner un simulateur ou un appareil iOS 17+.
4. **Product → Run** (⌘R).

L’onboarding puis le contenu principal s’affichent ; le coach IA est accessible depuis l’onglet prévu (avec ou sans modèle local selon le Master Switch et le Hardware Check).

---

## Structure du Projet (aperçu)

- **Entrée** : `MuscuApp.swift` — `WindowGroup` + `modelContainer(for: [...])`, racine `OnboardingContainerView`.
- **Coach IA** : `AICoachView` / `AICoachViewModel` (Observation), `LLMManager` (Mistral MLX), `CoachProtocolApplier` (Deload / Full Rest / Blessure), `AICoachActionParser` (`[ACTION: ...]`).
- **Modèle & Téléchargement** : `AIModelDownloader`, `AIModelDownloadView`, `MistralModelStorage`, `ModelFiles` (URLs Hugging Face).
- **Hardware** : `HardwareManager` (RAM 8 Go).
- **Données** : `Models.swift`, `DataController`, persistance SwiftData.

---

*Elite Architect — Performance, privacy, precision.*
