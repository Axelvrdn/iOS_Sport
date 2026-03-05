//
//  PerformanceCardView.swift
//  Muscu
//
//  Carte de saisie des performances (DA Elite) : Pickers natifs wheel, bouton Volt.
//

import SwiftUI

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

struct PerformanceCardView: View {
    @Environment(\.accentColor) private var accentColor
    @Environment(\.textOnAccentColor) private var textOnAccentColor
    let setIndex: Int
    let targetReps: String
    let currentEstimatedOneRM: Double
    let onValidate: (Int, Double, Bool) -> Void
    let onDismiss: () -> Void

    @State private var selectedReps: Int
    @State private var selectedWeight: Double
    @State private var showSuccess: Bool = false
    @State private var isPR: Bool = false

    private static let weightOptions: [Double] = Array(stride(from: 0, through: 300, by: 0.5))

    init(
        setIndex: Int,
        targetReps: String,
        currentEstimatedOneRM: Double,
        onValidate: @escaping (Int, Double, Bool) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.setIndex = setIndex
        self.targetReps = targetReps
        self.currentEstimatedOneRM = currentEstimatedOneRM
        self.onValidate = onValidate
        self.onDismiss = onDismiss
        let parsed = Int(targetReps.filter { $0.isNumber })
        self._selectedReps = State(initialValue: min(max(parsed ?? 10, 0), 100))
        self._selectedWeight = State(initialValue: 0)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(.white.opacity(0.3))
                    .frame(width: 40, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                Text("Série \(setIndex)")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.top, 8)

                if showSuccess && isPR {
                    nouveauRecordBandeau
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 28)
                }

                if showSuccess && !isPR {
                    successCheckmarkView
                        .padding(.vertical, 24)
                }

                if !showSuccess {
                    VStack(spacing: 0) {
                        pickersSection
                            .padding(.top, 8)
                        Button {
                            triggerHapticLight()
                            let new1RM = OneRMHelper.estimatedOneRM(weight: selectedWeight, reps: selectedReps) ?? 0
                            let pr = new1RM > currentEstimatedOneRM && selectedReps > 0 && selectedWeight > 0
                            if pr {
                                isPR = true
                            }
                            showSuccess = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + (pr ? 1.2 : 0.5)) {
                                onValidate(selectedReps, selectedWeight, pr)
                            }
                        } label: {
                            Text("Enregistrer la série")
                                .font(.headline)
                                .foregroundStyle(textOnAccentColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 28)
                        .disabled(selectedReps == 0)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.white.opacity(0.12))
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                }
            }
            .padding(.horizontal, 20)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 20)
            }
        }
    }

    private var pickersSection: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(spacing: 6) {
                Text("Répétitions")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Text("reps")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                ZStack {
                    Picker("", selection: $selectedReps) {
                        ForEach(0...100, id: \.self) { n in
                            Text("\(n)")
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.primary)
                                .tag(n)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 110)
                    .clipped()
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(accentColor.opacity(0.5), lineWidth: 1)
                        .allowsHitTesting(false)
                        .padding(4)
                }
                .frame(height: 110)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 6) {
                Text("Charge")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Text("kg")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                ZStack {
                    Picker("", selection: $selectedWeight) {
                        ForEach(Self.weightOptions, id: \.self) { w in
                            Text(weightString(w))
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.primary)
                                .tag(w)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 110)
                    .clipped()
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(accentColor.opacity(0.5), lineWidth: 1)
                        .allowsHitTesting(false)
                        .padding(4)
                }
                .frame(height: 110)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
    }

    private func weightString(_ w: Double) -> String {
        w == floor(w) ? "\(Int(w))" : String(format: "%.1f", w)
    }

    private var nouveauRecordBandeau: some View {
        HStack(spacing: 10) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 28))
                .foregroundStyle(accentColor)
                .shadow(color: .black.opacity(0.4), radius: 2)
            Text("NOUVEAU RECORD !")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(accentColor)
                .shadow(color: .black.opacity(0.5), radius: 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(accentColor.opacity(0.15))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(accentColor, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var successCheckmarkView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(accentColor)
            Text("Série enregistrée")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func triggerHapticLight() {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
    }
}
