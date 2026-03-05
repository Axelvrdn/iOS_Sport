//
//  YouTubeEmbedView.swift
//  Muscu
//
//  WKWebView pour afficher une vidéo YouTube en embed (utilisé par SessionRunnerView).
//

import SwiftUI
import WebKit

/// Extrait l'ID vidéo depuis une URL YouTube (watch ou youtu.be).
func youtubeVideoID(from urlString: String?) -> String? {
    guard let urlString = urlString?.trimmingCharacters(in: .whitespaces), !urlString.isEmpty else { return nil }
    if urlString.contains("youtu.be/") {
        return urlString.split(separator: "/").last.map(String.init)
    }
    guard let url = URL(string: urlString),
          let comp = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let query = comp.queryItems?.first(where: { $0.name == "v" }) else { return nil }
    return query.value
}

struct YouTubeEmbedView: View {
    let videoUrl: String?
    /// Coins arrondis (défaut 24 pour DA Elite).
    var cornerRadius: CGFloat = 24

    var body: some View {
        Group {
            if let id = youtubeVideoID(from: videoUrl) {
                YouTubeWebViewRepresentable(videoID: id)
                    .aspectRatio(16/9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                EmptyView()
            }
        }
    }
}

private struct YouTubeWebViewRepresentable: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let embed = "https://www.youtube.com/embed/\(videoID)?playsinline=1&rel=0"
        guard let url = URL(string: embed) else { return }
        webView.load(URLRequest(url: url))
    }
}
