//
//  AIModelDownloader.swift
//  Muscu
//
//  Service de téléchargement du modèle Mistral (Hugging Face) vers Application Support/MistralModel.
//  Vérifie les fichiers existants, progression en temps réel, gestion erreurs (disque, Wi‑Fi).
//

import Foundation

// MARK: - URLs des fichiers du modèle (Hugging Face)

struct ModelFiles {
    static let baseURLString = "https://huggingface.co/mlx-community/Mistral-7B-Instruct-v0.3-4bit-mlx/resolve/main"

    /// Fichiers requis pour le modèle MLX (ordre : config/tokenizer puis poids).
    /// Utiliser `model.safetensors` (repo HF mlx-community). LLMManager charge depuis le même dossier avec ces noms.
    static let fileNames: [String] = [
        "config.json",
        "tokenizer_config.json",
        "tokenizer.json",
        "model.safetensors"
    ]

    static var baseURL: URL {
        URL(string: baseURLString)!
    }

    static func url(for fileName: String) -> URL {
        // On force le téléchargement du fichier brut côté Hugging Face.
        var components = URLComponents(url: baseURL.appendingPathComponent(fileName), resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        items.append(URLQueryItem(name: "download", value: "true"))
        components?.queryItems = items
        return components?.url ?? baseURL.appendingPathComponent(fileName)
    }

    static var allURLs: [(fileName: String, url: URL)] {
        fileNames.map { ($0, url(for: $0)) }
    }
}

// MARK: - Dossier de stockage local

enum MistralModelStorage {
    /// Répertoire Application Support/MistralModel.
    static var directoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MistralModel", isDirectory: true)
        return dir
    }

    static func fileURL(for fileName: String) -> URL {
        directoryURL.appendingPathComponent(fileName)
    }

    /// Crée le répertoire s’il n’existe pas.
    static func createDirectoryIfNeeded() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directoryURL.path) {
            try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    /// Vérifie si un fichier est déjà présent (taille > 0 pour éviter les fichiers vides).
    static func hasFile(_ fileName: String) -> Bool {
        let url = fileURL(for: fileName)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return false }
        return size > 0
    }

    /// Liste des fichiers à télécharger (absents ou vides).
    static func filesToDownload() -> [String] {
        ModelFiles.fileNames.filter { !hasFile($0) }
    }
}

// MARK: - Downloader (URLSession, progression, erreurs)

@Observable
final class AIModelDownloader: NSObject {
    /// Progression globale 0...1 (pour la vue).
    var downloadProgress: Double = 0
    /// Octets téléchargés pour le fichier en cours (affichage taille).
    var totalBytesWritten: Int64 = 0
    /// Octets attendus pour le fichier en cours (ou total si connu).
    var totalBytesExpected: Int64 = 0
    /// Vitesse courante (octets/s).
    var downloadSpeed: Double = 0
    /// Message d’erreur affiché à l’utilisateur.
    var errorMessage: String?
    /// Téléchargement terminé avec succès.
    var isCompleted: Bool = false
    /// Téléchargement en cours.
    var isDownloading: Bool = false
    /// Nom du fichier en cours (pour logs / debug).
    var currentFileName: String?

    private var session: URLSession?
    private var currentTask: URLSessionDownloadTask?
    private var filesToDownload: [String] = []
    private var currentFileIndex: Int = 0
    private var speedUpdateTimer: Timer?
    private var lastBytes: Int64 = 0
    private var lastSpeedDate: Date = .init()

    override init() {
        super.init()
    }

    /// Supprime tout le contenu du dossier Application Support/MistralModel (deep clean).
    static func clearModelFolder() {
        let fm = FileManager.default
        let dir = MistralModelStorage.directoryURL
        do {
            if fm.fileExists(atPath: dir.path) {
                let contents = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                for url in contents {
                    try fm.removeItem(at: url)
                }
            }
        } catch {
            print("[AIModelDownloader] Échec du nettoyage du dossier modèle: \(error)")
        }
    }

    /// Lance le téléchargement des fichiers manquants (ne refait pas les fichiers déjà présents).
    func startDownload() {
        guard !isDownloading else { return }
        errorMessage = nil
        isCompleted = false
        downloadProgress = 0
        totalBytesWritten = 0
        totalBytesExpected = 0
        downloadSpeed = 0
        currentFileName = nil
        lastBytes = 0
        lastSpeedDate = Date()

        do {
            try MistralModelStorage.createDirectoryIfNeeded()
        } catch {
            errorMessage = "Impossible de créer le dossier du modèle."
            return
        }

        filesToDownload = MistralModelStorage.filesToDownload()
        if filesToDownload.isEmpty {
            isCompleted = true
            return
        }

        isDownloading = true
        currentFileIndex = 0
        startSpeedTimer()
        downloadNextFile()
    }

    func cancelDownload() {
        currentTask?.cancel()
        currentTask = nil
        session?.invalidateAndCancel()
        session = nil
        speedUpdateTimer?.invalidate()
        speedUpdateTimer = nil
        isDownloading = false
    }

    private func startSpeedTimer() {
        speedUpdateTimer?.invalidate()
        speedUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateSpeed()
        }
        RunLoop.main.add(speedUpdateTimer!, forMode: .common)
    }

    private func updateSpeed() {
        guard isDownloading else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSpeedDate)
        guard elapsed >= 0.25 else { return }
        downloadSpeed = Double(totalBytesWritten - lastBytes) / elapsed
        lastBytes = totalBytesWritten
        lastSpeedDate = now
    }

    private func downloadNextFile() {
        guard currentFileIndex < filesToDownload.count else {
            finishDownload(success: true)
            return
        }

        let fileName = filesToDownload[currentFileIndex]
        let remoteURL = ModelFiles.url(for: fileName)
        currentFileName = fileName
        totalBytesWritten = 0
        totalBytesExpected = 0

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        currentTask = session?.downloadTask(with: remoteURL)
        currentTask?.resume()
    }

    private func finishDownload(success: Bool) {
        speedUpdateTimer?.invalidate()
        speedUpdateTimer = nil
        currentTask = nil
        session?.invalidateAndCancel()
        session = nil
        isDownloading = false
        if success {
            isCompleted = true
        }
    }

    private static func userFacingError(from error: NSError) -> String {
        if error.domain == NSURLErrorDomain {
            switch error.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return "Connexion perdue. Vérifiez le Wi‑Fi ou les données."
            case NSURLErrorCancelled:
                return ""
            default:
                return error.localizedDescription
            }
        }
        if error.domain == NSPOSIXErrorDomain && error.code == 28 {
            return "Espace disque insuffisant pour le modèle."
        }
        return error.localizedDescription
    }
}

// MARK: - URLSessionDownloadDelegate

extension AIModelDownloader: URLSessionDownloadDelegate {

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard currentFileIndex < filesToDownload.count else { return }
        let fileName = filesToDownload[currentFileIndex]

        // Validation du MIME type pour éviter d'enregistrer des pages HTML d'erreur.
        if let httpResponse = downloadTask.response as? HTTPURLResponse {
            let mime = httpResponse.mimeType ?? ""
            if fileName.hasSuffix(".json") {
                let allowedJSON = ["application/json", "text/json"]
                if !allowedJSON.contains(mime) {
                    print("[AIModelDownloader] MIME invalide pour \(fileName): \(mime)")
                    errorMessage = "Le téléchargement de \(fileName) semble invalide (type: \(mime))."
                    try? FileManager.default.removeItem(at: location)
                    finishDownload(success: false)
                    return
                }
            } else {
                // Fichiers binaires : on rejette clairement le HTML.
                if mime == "text/html" {
                    print("[AIModelDownloader] MIME HTML inattendu pour \(fileName): \(mime)")
                    errorMessage = "Le téléchargement de \(fileName) semble invalide."
                    try? FileManager.default.removeItem(at: location)
                    finishDownload(success: false)
                    return
                }
            }
        }

        let destinationURL = MistralModelStorage.fileURL(for: fileName)
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)

            // Validation rapide de config.json juste après téléchargement.
            if fileName == "config.json" {
                do {
                    let data = try Data(contentsOf: destinationURL)
                    _ = try JSONSerialization.jsonObject(with: data, options: [])
                } catch {
                    print("[AIModelDownloader] config.json invalide, suppression et deep clean: \(error)")
                    try? FileManager.default.removeItem(at: destinationURL)
                    AIModelDownloader.clearModelFolder()
                    errorMessage = "Le fichier de configuration du modèle est corrompu. Le téléchargement sera relancé."
                    finishDownload(success: false)
                    return
                }
            }
        } catch {
            errorMessage = "Impossible d’enregistrer \(fileName)."
            finishDownload(success: false)
            return
        }
        currentFileIndex += 1
        downloadNextFile()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        self.totalBytesWritten = totalBytesWritten
        self.totalBytesExpected = totalBytesExpectedToWrite
        updateOverallProgress()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error as NSError? else { return }
        if error.code == NSURLErrorCancelled { return }
        let msg = Self.userFacingError(from: error)
        if !msg.isEmpty {
            errorMessage = msg
        }
        finishDownload(success: false)
    }

    /// Progression globale : (fichiers terminés + progression du fichier en cours) / nombre total de fichiers.
    private func updateOverallProgress() {
        let n = Double(filesToDownload.count)
        guard n > 0 else { return }
        let fileProgress = totalBytesExpected > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpected)
            : 0
        downloadProgress = (Double(currentFileIndex) + fileProgress) / n
    }
}
