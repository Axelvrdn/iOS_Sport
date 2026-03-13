//
//  AIModelDownloader.swift
//  Muscu
//
//  Service de téléchargement du modèle local (Phi-3 Mini 4-bit MLX) vers Application Support/Phi3Model.
//  Vérifie les fichiers existants, progression en temps réel, gestion erreurs (disque, Wi‑Fi).
//

import Foundation

// MARK: - URLs des fichiers du modèle (Hugging Face)

struct ModelFiles {
    /// Modèle cible : Phi-3 Mini 4k instruct 4-bit MLX (modèle agile ~2 Go).
    /// Repo Hugging Face : mlx-community/Phi-3-mini-4k-instruct-4bit
    static let baseURLString = "https://huggingface.co/mlx-community/Phi-3-mini-4k-instruct-4bit/resolve/main"

    /// Fichiers requis pour le modèle MLX (ordre : config/tokenizer puis poids).
    /// Utiliser `model.safetensors` (repo HF mlx-community). LLMManager charge depuis le même dossier avec ces noms.
    static let fileNames: [String] = [
        "config.json",
        "tokenizer_config.json",
        "tokenizer.json",
        "model.safetensors"
    ]

    static var baseURL: URL {
        guard let url = URL(string: baseURLString) else {
            fatalError("[ModelFiles] baseURLString invalide: \(baseURLString)")
        }
        return url
    }

    /// Construit l’URL de téléchargement sans paramètre ?download=true pour éviter certains 404/MIME bizarres.
    static func url(for fileName: String) -> URL {
        let url = baseURL.appendingPathComponent(fileName)
        print("🚀 Tentative finale sur : \(url.absoluteString)")
        return url
    }

    static var allURLs: [(fileName: String, url: URL)] {
        fileNames.map { ($0, url(for: $0)) }
    }
}

// MARK: - Dossier de stockage local

enum MistralModelStorage {
    /// Répertoire Application Support/Phi3Model.
    static var directoryURL: URL {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        guard let appSupport = urls.first else {
            fatalError("[MistralModelStorage] Impossible de récupérer le dossier Application Support.")
        }
        return appSupport.appendingPathComponent("Phi3Model", isDirectory: true)
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

    /// Emplacement sur disque où stocker les données de reprise pour le téléchargement des poids.
    static var weightsResumeDataURL: URL {
        directoryURL.appendingPathComponent("model.safetensors.resume")
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
    /// Token Hugging Face pour accéder au repo du modèle.
    /// Remplacez la valeur par votre token personnel (évitez de le committer en clair).

    private var session: URLSession?
    private var currentTask: URLSessionDownloadTask?
    private var filesToDownload: [String] = []
    private var currentFileIndex: Int = 0
    private var speedUpdateTimer: Timer?
    private var lastBytes: Int64 = 0
    private var lastSpeedDate: Date = .init()
    /// Données de reprise pour le téléchargement des poids (model.safetensors).
    private var weightsResumeData: Data?

    override init() {
        super.init()
    }

    deinit {
        session?.invalidateAndCancel()
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

    /// Supprime les téléchargements partiels (.tmp / .part) dans Application Support/MistralModel.
    /// Évite de reprendre sur un fichier corrompu si un précédent téléchargement a échoué.
    static func clearPartialDownloads() {
        let fm = FileManager.default
        let dir = MistralModelStorage.directoryURL
        guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in contents {
            let name = url.lastPathComponent
            if name.hasSuffix(".tmp") || name.hasSuffix(".part") {
                try? fm.removeItem(at: url)
            }
        }
    }

    /// Lance le téléchargement des fichiers manquants (ne refait pas les fichiers déjà présents).
    func startDownload() {
        guard !isDownloading else { return }

        // Reset complet de l'état.
        errorMessage = nil
        isCompleted = false
        downloadProgress = 0
        totalBytesWritten = 0
        totalBytesExpected = 0
        downloadSpeed = 0
        currentFileName = nil
        lastBytes = 0
        lastSpeedDate = Date()
        currentFileIndex = 0

        Task { @MainActor in
            do {
                try MistralModelStorage.createDirectoryIfNeeded()
            } catch {
                errorMessage = "Impossible de créer le dossier du modèle."
                return
            }

            // Test de connexion préventif : vérifier que config.json répond bien 200 avant de lancer les gros fichiers.
            let ok = await preflightCheckConfigJSON()
            guard ok else {
                // preflightCheckConfigJSON renseigne déjà errorMessage et les logs en console.
                return
            }

            // Nettoyage des fichiers partiels avant de déterminer ce qu'il reste à télécharger.
            Self.clearPartialDownloads()

            filesToDownload = MistralModelStorage.filesToDownload()
            if filesToDownload.isEmpty {
                isCompleted = true
                return
            }

            isDownloading = true
            startSpeedTimer()
            downloadNextFile()
        }
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
        if let timer = speedUpdateTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
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

        print("🚀 STARTING FILE: \(fileName) (\(currentFileIndex + 1)/\(filesToDownload.count))")

        // Avant de lancer le téléchargement des poids, vérifier qu'il reste au moins ~6 Go de libre.
        if fileName == "model.safetensors", !hasEnoughDiskSpaceForWeights() {
            return
        }

        // URLSession suit les redirections par défaut ; pas de delegate qui les bloque.
        let config = URLSessionConfiguration.default
        if fileName == "config.json" {
            // Petit fichier : timeout plus court pour éviter de stagner inutilement.
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 120
        } else {
            // Fichiers lourds (tokenizer + poids) : timeout généreux.
            config.timeoutIntervalForRequest = 120
            config.timeoutIntervalForResource = 7200
        }
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)

        var request = URLRequest(url: remoteURL)
        request.setValue("Bearer \(hfToken)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        print("DEBUG: Envoi de la requête vers \(remoteURL.absoluteString) avec token (masqué)")

        // Pour les gros fichiers (poids du modèle), on essaie de reprendre si des resumeData existent.
        if fileName == "model.safetensors",
           let data = weightsResumeData ?? (try? Data(contentsOf: MistralModelStorage.weightsResumeDataURL)),
           !data.isEmpty {
            print("[AIModelDownloader] Reprise du téléchargement des poids depuis des resumeData.")
            currentTask = session?.downloadTask(withResumeData: data)
        } else {
            currentTask = session?.downloadTask(with: request)
        }
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
            // Tous les fichiers ont été traités, on vérifie l'intégrité du modèle (présence + taille minimale des fichiers).
            if verifyModelIntegrity() {
                isCompleted = true
            }
        }
    }

    /// Appel léger sur config.json pour vérifier que le modelID / repo Hugging Face est correct avant le gros téléchargement (async).
    /// Retourne true si HTTP 200, sinon renseigne errorMessage et log le corps de réponse.
    private func preflightCheckConfigJSON() async -> Bool {
        let configURL = ModelFiles.url(for: "config.json")
        var request = URLRequest(url: configURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(hfToken)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "Réponse inattendue lors de la vérification du modèle Hugging Face."
                return false
            }
            guard http.statusCode == 200 else {
                if http.statusCode == 404 {
                    print("[AIModelDownloader] Preflight config.json 404 – vérifiez l'identifiant du modèle Hugging Face.")
                    errorMessage = "Erreur : Identifiant de modèle Hugging Face incorrect (404 sur config.json)."
                } else {
                    let bodyPreview = String(data: data, encoding: .utf8) ?? "<vide>"
                    print("[AIModelDownloader] Preflight config.json HTTP \(http.statusCode). Corps éventuel : \(bodyPreview)")
                    errorMessage = "Erreur serveur Hugging Face (HTTP \(http.statusCode)) lors de la vérification du modèle."
                }
                return false
            }
        } catch {
            print("[AIModelDownloader] Preflight config.json échec transport: \(error)")
            errorMessage = Self.userFacingError(from: error as NSError)
            return false
        }

        print("[AIModelDownloader] Preflight config.json OK (200) pour \(configURL.absoluteString)")
        return true
    }

    /// Vérifie qu'il reste au moins ~6 Go sur le volume où réside Application Support avant de télécharger les poids.
    private func hasEnoughDiskSpaceForWeights(minFreeBytes: Int64 = 6 * 1024 * 1024 * 1024) -> Bool {
        let dir = MistralModelStorage.directoryURL
        do {
            let values = try dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let cap = values.volumeAvailableCapacityForImportantUsage {
                let free = Int64(cap)
                if free < minFreeBytes {
                    let freeGB = Double(free) / (1024 * 1024 * 1024)
                    let formatted = String(format: "%.2f", freeGB)
                    print("[AIModelDownloader] Espace disque insuffisant: \(formatted) Go libres (< 6 Go requis).")
                    errorMessage = "Espace disque insuffisant : au moins 6 Go libres sont requis pour télécharger le modèle."
                    finishDownload(success: false)
                    return false
                }
            }
        } catch {
            // En cas d'erreur de récupération, on ne bloque pas mais on log.
            print("[AIModelDownloader] Impossible de lire l'espace disque disponible: \(error)")
        }
        return true
    }

    /// Vérifie que tous les fichiers du modèle sont présents et non vides, avec une taille minimale pour les poids.
    private func verifyModelIntegrity() -> Bool {
        var ok = true
        for name in ModelFiles.fileNames {
            let url = MistralModelStorage.fileURL(for: name)
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? Int64, size > 0 else {
                print("[AIModelDownloader] Fichier manquant ou vide: \(name)")
                ok = false
                continue
            }
            if name == "model.safetensors" {
                // Sanity check : les poids doivent faire au moins ~1 Go en 4-bit ; en‑dessous, on considère le fichier suspect.
                let minWeightsSize: Int64 = 1 * 1024 * 1024 * 1024
                if size < minWeightsSize {
                    print("[AIModelDownloader] Taille des poids suspecte (\(size) octets) pour \(name).")
                    ok = false
                }
            }
        }
        if !ok {
            errorMessage = "Le modèle téléchargé semble incomplet ou corrompu. Veuillez réessayer après avoir libéré de l'espace disque."
        }
        return ok
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

        print("[AIModelDownloader] Fichier temporaire reçu pour \(currentFileName ?? fileName)")

        if let httpResponse = downloadTask.response as? HTTPURLResponse {
            // Gestion des erreurs HTTP : log complet du corps pour diagnostiquer les réponses Hugging Face (rate limit, invalid token, etc.).
            if httpResponse.statusCode != 200 {
                if let data = try? Data(contentsOf: location),
                   let body = String(data: data, encoding: .utf8) {
                    print("[AIModelDownloader] HTTP \(httpResponse.statusCode) pour \(fileName). Corps:\n\(body)")
                } else {
                    print("[AIModelDownloader] HTTP \(httpResponse.statusCode) pour \(fileName) (corps illisible)")
                }
                errorMessage = "Le serveur a renvoyé une erreur (HTTP \(httpResponse.statusCode))."
                try? FileManager.default.removeItem(at: location)
                finishDownload(success: false)
                return
            }

            // Validation du MIME type : pour config.json on tolère aussi text/plain ; pour le binaire on reste strict.
            let mime = (httpResponse.value(forHTTPHeaderField: "Content-Type")?.split(separator: ";").first.map(String.init) ?? httpResponse.mimeType ?? "").trimmingCharacters(in: .whitespaces)
            if fileName.hasSuffix(".json") {
                // Hugging Face renvoie parfois text/plain pour un contenu JSON valide : on l'accepte.
                let allowedJSON = ["application/json", "text/json", "text/plain"]
                if !allowedJSON.contains(mime) {
                    print("[AIModelDownloader] MIME invalide pour \(fileName): '\(mime)' (attendu: application/json)")
                    errorMessage = "Le téléchargement de \(fileName) semble invalide (type: \(mime))."
                    try? FileManager.default.removeItem(at: location)
                    finishDownload(success: false)
                    return
                }
            } else {
                // Fichiers binaires (.safetensors) : uniquement application/octet-stream (ou type vide si non envoyé).
                let allowedBinary = ["application/octet-stream", "application/x-safetensors"]
                if !mime.isEmpty && !allowedBinary.contains(mime) {
                    print("[AIModelDownloader] MIME invalide pour \(fileName): '\(mime)' (attendu: application/octet-stream)")
                    errorMessage = "Le téléchargement de \(fileName) semble invalide (type: \(mime))."
                    try? FileManager.default.removeItem(at: location)
                    finishDownload(success: false)
                    return
                }
                if mime == "text/html" || mime == "application/json" {
                    print("[AIModelDownloader] Réponse non binaire pour \(fileName): \(mime)")
                    errorMessage = "Le téléchargement de \(fileName) semble invalide."
                    try? FileManager.default.removeItem(at: location)
                    finishDownload(success: false)
                    return
                }
            }
        }

        let destinationURL = MistralModelStorage.fileURL(for: fileName)
        do {
            // Utiliser replaceItem pour écraser proprement d'anciennes versions éventuellement corrompues.
            let fm = FileManager.default
            _ = try fm.replaceItem(
                at: destinationURL,
                withItemAt: location,
                backupItemName: nil,
                options: [],
                resultingItemURL: nil
            )

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
            print("[AIModelDownloader] Erreur lors du déplacement de \(fileName): \(error)")
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
        let percent = downloadProgress * 100
        let writtenMB = totalBytesWritten / 1_000_000
        let expectedMB = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite / 1_000_000 : -1
        let percentString = String(format: "%.2f", percent)
        if expectedMB > 0 {
            print("📥 DOWNLOAD PROGRESS: \(percentString)% | \(writtenMB)MB / \(expectedMB)MB")
        } else {
            print("📥 DOWNLOAD PROGRESS: \(percentString)% | \(writtenMB)MB / ?MB")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error as NSError? else { return }
        if error.code == NSURLErrorCancelled { return }

        // Pour les poids, on tente de récupérer des resumeData pour une reprise ultérieure.
        if let currentFileName,
           currentFileName == "model.safetensors",
           let resume = error.userInfo[NSURLSessionDownloadTaskResumeData] as? Data,
           !resume.isEmpty {
            weightsResumeData = resume
            try? resume.write(to: MistralModelStorage.weightsResumeDataURL)
            print("[AIModelDownloader] Téléchargement des poids interrompu, resumeData sauvegardées pour une reprise.")
        }

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
