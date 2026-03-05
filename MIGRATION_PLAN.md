# Plan de migration — Mode Performance Native (iOS 17+)

## Vue d'ensemble

Refonte structurelle pour aligner l'application sur le standard 2026 : framework Observation, AI Master Switch, cible iOS 17.0 et préparation à l’intégration du modèle MLX.

---

## 1. Migration vers le framework Observation

### 1.1 ViewModels concernés

| Fichier | Avant | Après |
|---------|--------|--------|
| `AICoachViewModel.swift` | `class AICoachViewModel: ObservableObject` + `@Published` | `@Observable final class AICoachViewModel` |
| `WorkoutManager.swift` | `class WorkoutManager: ObservableObject` + `@Published` | `@Observable final class WorkoutManager` |
| `CalendarManager.swift` | `class CalendarManager: ObservableObject` + `@Published` | `@Observable final class CalendarManager` |
| `EventKitManager.swift` | `class EventKitManager: ObservableObject` + `@Published` | `@Observable final class EventKitManager` |
| `ContentView.swift` (TabBarVisibilityStore) | `class TabBarVisibilityStore: ObservableObject` + `@Published` | `@Observable final class TabBarVisibilityStore` |
| `OnboardingContainerView.swift` (OnboardingState) | `class OnboardingState: ObservableObject` + `@Published` | `@Observable final class OnboardingState` |

### 1.2 Changements dans les vues

- **Possession du ViewModel (création dans la vue)**  
  `@StateObject private var x = ...` → `@State private var x = ...`
- **Réception en paramètre**  
  `@ObservedObject var state: OnboardingState` → paramètre normal `var state: OnboardingState` (Observation suit l’accès aux propriétés).
- **Import**  
  Ajout de `import Observation` dans les fichiers contenant des types `@Observable`. Suppression de `import Combine` là où il ne sert plus qu’à `ObservableObject`/`@Published`.

### 1.3 Bénéfices

- Moins de re-renders : SwiftUI ne se met à jour que lorsque les propriétés réellement lues dans le body changent.
- Code plus simple : plus de `@Published` ni de `objectWillChange`.
- Alignement avec les bonnes pratiques Swift 5.9+ et SwiftUI moderne.

---

## 2. AI Master Switch

### 2.1 HardwareManager (nouveau)

- **Rôle** : Vérifier si l’appareil est compatible avec l’IA locale lourde (modèle type MLX).
- **Critère** : RAM ≥ 8 Go (classe iPhone 15 Pro / M1). Utilisation de `ProcessInfo.processInfo.physicalMemory` avec un seuil adapté (ex. 6 Go rapportés pour couvrir les appareils 8 Go).
- **API** :
  - `HardwareManager.shared.hasMinimumRAMForLocalAI() -> Bool`
  - `HardwareManager.shared.isLocalAISupported` (calculé)
  - Optionnel : libellé appareil pour messages d’avertissement.

### 2.2 Réglages

- **Clé** : `UserDefaults` / `@AppStorage` dédiée (ex. `localAIEnabledKey`).
- **Option** : « Activer l’IA Locale (Beta) » (toggle).
- **Comportement** :
  - Si l’appareil n’est **pas** compatible : afficher un avertissement et empêcher l’activation (ou autoriser le toggle mais forcer le mode léger côté ViewModel).
  - Si l’utilisateur tente d’activer sur appareil non compatible : message clair (ex. « Nécessite un appareil avec au moins 8 Go de RAM (iPhone 15 Pro, M1 ou supérieur). »).

### 2.3 AICoachViewModel

- **Sécurité** : Si « Activer l’IA Locale » est **OFF**, le ViewModel utilise **uniquement** la logique de réponse légère (règles métier, `processUserMessage`) et **ne charge jamais** le modèle lourd en mémoire.
- **Préparation MLX** : Lors de l’intégration future du modèle, un branchement du type `if useLocalAIModel && HardwareManager.shared.hasMinimumRAMForLocalAI() { … load model … }` garantit que le modèle n’est chargé que lorsque l’option est activée et l’appareil compatible.

---

## 3. Nettoyage global & standard 2026

### 3.1 Cible de déploiement

- **Minimum** : iOS 17.0.
- **Fichier** : `Muscu.xcodeproj/project.pbxproj` — `IPHONEOS_DEPLOYMENT_TARGET = 17.0` (configurations Debug et Release au niveau projet, et au niveau cible si défini).

### 3.2 APIs et performances

- **Listes / grilles** : Vérifier l’usage de `List`, `LazyVStack`, `LazyVGrid` ; privilégier les APIs récentes (iOS 17+) et les identifiants stables pour de meilleures perfs.
- **CalendarManager** : Supprimer les branches `#available(iOS 17.0)` devenues inutiles ; utiliser systématiquement `requestFullAccessToEvents()`.
- **Mémoire** : Pas d’instances globales lourdes inutiles ; le modèle MLX ne sera chargé qu’à la demande et uniquement si l’AI Master Switch est ON et l’appareil compatible.

### 3.3 Préparation MLX

- Garder une séparation nette entre « moteur de règles » (toujours actif) et « modèle local » (optionnel, derrière le switch).
- Documenter dans le code les points d’injection pour le futur chargement du modèle.

---

## 4. Ordre d’exécution recommandé

1. Mettre la cible à iOS 17.0 et nettoyer les `#available` (ex. CalendarManager).
2. Introduire `HardwareManager` et l’option « Activer l’IA Locale (Beta) » dans les réglages ; brancher le flag dans `AICoachViewModel` et la vue AI Coach.
3. Migrer tous les ViewModels vers `@Observable` (suppression de `ObservableObject` et `@Published`).
4. Mettre à jour toutes les vues : `@StateObject` → `@State`, suppression de `@ObservedObject`, ajout de `import Observation` où nécessaire.
5. Vérifier les listes/grilles et la gestion mémoire (revue manuelle + tests).

---

## 5. Fichiers modifiés / ajoutés

| Action | Fichier |
|--------|---------|
| **Créer** | `Muscu/HardwareManager.swift` |
| **Modifier** | `Muscu/AICoachViewModel.swift` |
| **Modifier** | `Muscu/AICoachView.swift` |
| **Modifier** | `Muscu/SettingsView.swift` (AICoachSettingsView + clé AppStorage) |
| **Modifier** | `Muscu/WorkoutManager.swift` |
| **Modifier** | `Muscu/CalendarManager.swift` |
| **Modifier** | `Muscu/EventKitManager.swift` |
| **Modifier** | `Muscu/ContentView.swift` |
| **Modifier** | `Muscu/OnboardingContainerView.swift` |
| **Modifier** | `Muscu/OnboardingStep1View.swift` … `OnboardingStep4View.swift`, `OnboardingFinalView.swift` |
| **Modifier** | `Muscu/WorkoutView.swift` |
| **Modifier** | `Muscu/SchedulingSheet.swift` |
| **Modifier** | `Muscu.xcodeproj/project.pbxproj` |

Ce plan peut servir de checklist pour la migration et la revue de code.
