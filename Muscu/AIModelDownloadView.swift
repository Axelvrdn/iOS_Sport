//
//  AIModelDownloadView.swift
//  Muscu
//
//  DA "Elite Architect" : overlay plein écran de téléchargement du modèle IA locale.
//  Cercle de progression avec glow, statuts "hacker", URLSessionDownloadDelegate, célébration à la fin.
//

import SwiftUI
import UIKit

// MARK: - Clé première activation IA Locale

/// À true une fois le modèle téléchargé ; affiche l’overlay de téléchargement uniquement au premier activation.
let localAIModelDownloadCompletedKey = "localAIModelDownloadCompleted"

// MARK: - Couleurs Elite Architect

private let DownloadBgDark = Color(hex: "0F1115")

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - Messages de statut "Hacker" (rotation 2 s)

private let statusMessages: [String] = [
    "Initialisation des poids neuronaux...",
    "Optimisation du cache Metal...",
    "Chargement de la base biomécanique...",
    "Calibration des tenseurs...",
    "Vérification des noyaux GPU...",
    "Compression des embeddings...",
    "Synchronisation des couches...",
    "Validation du graphe de calcul..."
]

// MARK: - Vue principale

struct AIModelDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accentColor) private var accentColor
    @AppStorage(localAIModelDownloadCompletedKey) private var modelDownloadCompleted: Bool = false
    @AppStorage(localAIEnabledKey) private var localAIEnabled: Bool = false

    @State private var downloader = AIModelDownloader()
    @State private var showErrorAlert: Bool = false
    @State private var showCelebration: Bool = false
    @State private var celebrationOpacity: Double = 0

    private let statusRotationInterval: TimeInterval = 2.0

    var body: some View {
        ZStack {
            DownloadBgDark
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer().frame(height: 60)

                // Cercle de progression avec glow
                ZStack {
                    // Piste de fond
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 14)
                        .frame(width: 200, height: 200)

                    // Progression
                    Circle()
                        .trim(from: 0, to: downloader.downloadProgress)
                        .stroke(
                            AngularGradient(
                                colors: [accentColor, accentColor.opacity(0.85), accentColor],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round)
                        )
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: accentColor.opacity(0.9), radius: 20, x: 0, y: 0)
                        .shadow(color: accentColor.opacity(0.6), radius: 40, x: 0, y: 0)
                        .animation(.easeOut(duration: 0.25), value: downloader.downloadProgress)

                    // Pourcentage au centre
                    Text("\(Int(round(downloader.downloadProgress * 100))) %")
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }

                // Statut "Hacker" (défilement 2 s)
                TimelineView(.periodic(from: .now, by: statusRotationInterval)) { context in
                    let idx = downloader.isCompleted ? 0 : (Int(context.date.timeIntervalSince1970 / statusRotationInterval) % statusMessages.count)
                    Text(statusMessages[idx])
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .frame(height: 44)
                        .animation(.easeInOut(duration: 0.3), value: idx)
                }

                // Taille et vitesse
                VStack(spacing: 6) {
                    Text(sizeText)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(speedText)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                // Annuler (tant que pas terminé)
                if !downloader.isCompleted && downloader.isDownloading {
                    Button {
                        downloader.cancelDownload()
                        localAIEnabled = false
                        dismiss()
                    } label: {
                        Text("Annuler")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.bottom, 48)
                }
            }
            .onAppear {
                downloader.startDownload()
            }
            .onDisappear {
                if !downloader.isCompleted {
                    downloader.cancelDownload()
                }
            }
            .onChange(of: downloader.errorMessage) { _, msg in
                if msg != nil { showErrorAlert = true }
            }
            .onChange(of: downloader.isCompleted) { _, completed in
                if completed {
                    triggerCelebration()
                }
            }
            .alert("Erreur de téléchargement", isPresented: $showErrorAlert) {
                Button("Réessayer") {
                    showErrorAlert = false
                    downloader.errorMessage = nil
                    downloader.startDownload()
                }
                Button("Annuler", role: .cancel) {
                    showErrorAlert = false
                    downloader.errorMessage = nil
                    localAIEnabled = false
                    dismiss()
                }
            } message: {
                if let msg = downloader.errorMessage {
                    Text(msg)
                }
            }
            .overlay {
                // Flash de célébration
                if showCelebration {
                    Rectangle()
                        .fill(.white)
                        .opacity(celebrationOpacity)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var sizeText: String {
        let written = ByteCountFormatter.string(fromByteCount: downloader.totalBytesWritten, countStyle: .file)
        let total = downloader.totalBytesExpected > 0
            ? ByteCountFormatter.string(fromByteCount: downloader.totalBytesExpected, countStyle: .file)
            : "…"
        return "\(written) / \(total)"
    }

    private var speedText: String {
        guard downloader.downloadSpeed > 0 else { return "Calcul..." }
        let speed = ByteCountFormatter.string(fromByteCount: Int64(downloader.downloadSpeed), countStyle: .file)
        return "\(speed)/s"
    }

    private func triggerCelebration() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        showCelebration = true
        withAnimation(.easeOut(duration: 0.15)) {
            celebrationOpacity = 0.7
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeOut(duration: 0.4)) {
                celebrationOpacity = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            modelDownloadCompleted = true
            showCelebration = false
            dismiss()
        }
    }
}

// MARK: - Prévisualisation

#Preview {
    AIModelDownloadView()
        .environment(\.accentColor, Color(hex: "D0FD3E"))
}
