//
//  ChatView.swift
//  Muscu
//
//  Simple chat interface with the AI Coach.
//

import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
}

struct ChatView: View {
    let strictnessLevel: Double

    @State private var messages: [ChatMessage] = [
        ChatMessage(text: "Salut, je suis ton coach IA. Comment tu te sens aujourd’hui ?", isUser: false)
    ]
    @State private var inputText: String = ""

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                VStack {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(messages) { message in
                                    HStack {
                                        if message.isUser {
                                            Spacer()
                                            bubble(for: message, color: .accentColor, alignment: .trailing, maxWidth: geo.size.width * 0.75)
                                        } else {
                                            bubble(for: message, color: Color(.secondarySystemBackground), alignment: .leading, maxWidth: geo.size.width * 0.75)
                                            Spacer()
                                        }
                                    }
                                    .id(message.id)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 8)
                        }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField("Dis au coach ce que tu ressens…", text: $inputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .padding(8)
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Coach IA")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    // MARK: - UI Helpers

    private func bubble(for message: ChatMessage, color: Color, alignment: HorizontalAlignment, maxWidth: CGFloat) -> some View {
        Text(message.text)
            .padding(10)
            .foregroundStyle(message.isUser ? Color.white : Color.primary)
            .background(color)
            .cornerRadius(12)
            .frame(maxWidth: maxWidth, alignment: alignment == .trailing ? .trailing : .leading)
    }

    // MARK: - Logic

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let userMessage = ChatMessage(text: trimmed, isUser: true)
        messages.append(userMessage)
        inputText = ""

        let coachReplyText = generateCoachReply(to: trimmed)
        let coachMessage = ChatMessage(text: coachReplyText, isUser: false)
        messages.append(coachMessage)
    }

    private func generateCoachReply(to text: String) -> String {
        let lowercased = text.lowercased()

        // Détection très simple de quelques intents
        let mentionsPain = lowercased.contains("épaule") || lowercased.contains("shoulder")
            || lowercased.contains("genou") || lowercased.contains("knee")
        let mentionsTired = lowercased.contains("fatigu") || lowercased.contains("tired")
            || lowercased.contains("épuisé") || lowercased.contains("crevé")

        let baseAdvice: String

        if mentionsPain {
            baseAdvice = "Tu mentionnes une douleur. On va adapter la séance en évitant de charger cette zone, et on va réduire légèrement le volume."
        } else if mentionsTired {
            baseAdvice = "Tu te sens fatigué. On peut alléger l’intensité aujourd’hui, tout en gardant un minimum d’activité pour ne pas casser la dynamique."
        } else {
            baseAdvice = "Je prends en compte ton retour et j’ajuste la séance pour optimiser ta progression tout en gérant la récupération."
        }

        let tonePrefix: String
        if strictnessLevel < 0.33 {
            tonePrefix = "OK, on va y aller en douceur aujourd’hui. "
        } else if strictnessLevel < 0.66 {
            tonePrefix = "Compris. On reste sérieux mais raisonnable. "
        } else {
            tonePrefix = "Pas d’excuses, mais on reste intelligents. "
        }

        let followUp: String
        if strictnessLevel < 0.33 {
            followUp = " Si la douleur augmente ou ne passe pas, on coupe court et on bascule sur du travail très léger ou du repos."
        } else if strictnessLevel < 0.66 {
            followUp = " On surveille les sensations pendant l’échauffement et on ajuste en temps réel."
        } else {
            followUp = " Tu donnes tout sur ce qui est possible sans douleur, mais tu respectes strictement les consignes sur la zone fragile."
        }

        return tonePrefix + baseAdvice + followUp
    }
}

#Preview {
    ChatView(strictnessLevel: 0.7)
}

