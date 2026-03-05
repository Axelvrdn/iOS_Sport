//
//  HardwareManager.swift
//  Muscu
//
//  Vérifie les capacités matérielles pour l'IA locale (modèle lourd type MLX).
//  Exigence : au moins 8 Go RAM (classe iPhone 15 Pro / M1).
//

import Foundation

/// Seuil minimal de RAM pour l'IA locale (8 Go classe).
/// Sur iOS, physicalMemory peut rapporter moins que la RAM physique totale ;
/// 6 Go rapportés couvrent les appareils 8 Go (iPhone 15 Pro, M1, etc.).
private let minimumBytesForLocalAI: UInt64 = 6 * 1024 * 1024 * 1024

/// Gestionnaire des capacités matérielles pour l'IA locale.
enum HardwareManager {

    /// Vérifie si l'appareil dispose d'au moins 8 Go de RAM (classe iPhone 15 Pro / M1).
    /// Utilise ProcessInfo.physicalMemory (mémoire disponible à l'app).
    static var hasMinimumRAMForLocalAI: Bool {
        ProcessInfo.processInfo.physicalMemory >= minimumBytesForLocalAI
    }

    /// Alias sémantique : appareil compatible avec l'IA locale (beta).
    static var isLocalAISupported: Bool {
        hasMinimumRAMForLocalAI
    }

    /// Message d'avertissement si l'utilisateur tente d'activer l'IA sur un appareil non compatible.
    static let unsupportedDeviceMessage = "L'IA locale nécessite un appareil avec au moins 8 Go de RAM (iPhone 15 Pro, M1 ou supérieur)."
}
