//
//  VisualTimePickerView.swift
//  Muscu
//
//  Rôle : Timeline visuelle type Calendrier (grille horaire 6h–23h, événements en lecture seule, bloc séance draggable avec snap 15 min et détection de conflit).
//  DA : Deep Charcoal & Volt — fond sombre, bloc avec glow Volt "magnétique".
//

import SwiftUI
import EventKit

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

private let PickerBackgroundDark = Color(hex: "0F1115")
private let PickerCardDark = Color(hex: "1C1F26")
private let startHour = 6
private let endHour = 23
private let hourHeight: CGFloat = 80
private let totalHours = endHour - startHour
private let timelineContentHeight: CGFloat = CGFloat(totalHours) * hourHeight

struct VisualTimePickerView: View {
    @Binding var selectedTime: Date
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentColor) private var accentColor
    let date: Date
    let durationMinutes: Int
    let dayEvents: [EKEvent]
    let sessionTitle: String
    /// Si défini (mode modification), le bloc est positionné à cette heure et centré au scroll. Sinon (nouvelle planif) → 19h.
    var initialDate: Date? = nil
    /// ID de l’événement calendrier de la séance en cours (pour ne pas l’afficher en gris dans les obstacles).
    var excludedEventID: String? = nil

    private let calendar = Calendar.current
    @State private var dragOffset: CGFloat = 0
    @State private var scrollProxy: ScrollViewProxy?
    @State private var dragTimer: Timer?

    private var pickerBackground: Color {
        colorScheme == .dark ? PickerBackgroundDark : Color(.systemGroupedBackground)
    }
    private var pickerHeaderBackground: Color {
        colorScheme == .dark ? PickerCardDark : Color(.secondarySystemGroupedBackground)
    }
    private var pickerVoltColor: Color {
        accentColor
    }
    private var blockTextOnVolt: Color {
        colorScheme == .dark ? PickerBackgroundDark : Color.black
    }

    private var startOfDay: Date {
        calendar.startOfDay(for: date)
    }

    private var sessionStart: Date {
        calendar.date(bySettingHour: calendar.component(.hour, from: selectedTime), minute: calendar.component(.minute, from: selectedTime), second: 0, of: startOfDay) ?? selectedTime
    }

    private var sessionEnd: Date {
        calendar.date(byAdding: .minute, value: durationMinutes, to: sessionStart) ?? sessionStart
    }

    private var hasConflict: Bool {
        dayEvents.contains { event in
            guard let start = event.startDate, let end = event.endDate else { return false }
            return sessionStart < end && sessionEnd > start
        }
    }

    private var sessionBlockY: CGFloat {
        timeToY(sessionStart) + dragOffset
    }

    private var sessionBlockHeight: CGFloat {
        CGFloat(durationMinutes) / 60.0 * hourHeight
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Calendrier (grille + événements + bloc) en arrière-plan
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        timelineGrid
                        eventsLayer
                        sessionBlockLayer(proxy: proxy)
                    }
                    .frame(height: timelineContentHeight)
                    .padding(.horizontal, 16)
                    .padding(.top, 56)
                    .background(pickerBackground)
                }
                .onAppear {
                    scrollProxy = proxy
                    if let initial = initialDate, calendar.isDate(initial, inSameDayAs: date) {
                        selectedTime = calendar.date(bySettingHour: calendar.component(.hour, from: initial), minute: calendar.component(.minute, from: initial), second: 0, of: startOfDay) ?? initial
                    } else {
                        selectedTime = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: startOfDay) ?? startOfDay
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        scrollToSession(proxy: proxy)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // En-tête heure choisie TOUJOURS au-dessus (lisibilité garantie)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Heure choisie")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(timeString(sessionStart))
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.primary)
                }
                .padding(.top, 12)
                .padding(.leading, 16)
                Spacer()
                if hasConflict {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text("Conflit")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(pickerHeaderBackground)
            .zIndex(10)
        }
        .background(pickerBackground)
    }

    // MARK: - Grille horaire (lignes + labels)

    private var timelineGrid: some View {
        VStack(spacing: 0) {
            ForEach(startHour..<endHour, id: \.self) { hour in
                HStack(alignment: .top, spacing: 12) {
                    Text(String(format: "%02d:00", hour))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                    Rectangle()
                        .fill(Color.primary.opacity(0.15))
                        .frame(height: 1)
                }
                .frame(height: hourHeight)
                .id("hour-\(hour)")
            }
        }
    }

    // MARK: - Événements du jour (blocs grisés)

    private var eventsLayer: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(dayEvents.enumerated()), id: \.offset) { _, event in
                if event.eventIdentifier != excludedEventID,
                   let start = event.startDate, let end = event.endDate {
                    let y = timeToY(start)
                    let h = max(20, CGFloat(end.timeIntervalSince(start) / 3600) * hourHeight)
                    if y >= 0 && y + h <= timelineContentHeight {
                        eventBlock(title: event.title ?? "Événement", y: y, height: h)
                    }
                }
            }
        }
        .padding(.leading, 48)
    }

    private func eventBlock(title: String, y: CGFloat, height: CGFloat) -> some View {
        let w: CGFloat = 180
        let cx = 48 + w / 2
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(8)
        .frame(width: w, height: max(24, height - 4), alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? PickerCardDark : Color(.tertiarySystemFill))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.2 : 0.15), lineWidth: 1)
                )
        )
        .position(x: cx, y: y + height / 2 - 2)
    }

    // MARK: - Bloc séance (draggable, Liquid Glass style)

    private func sessionBlockLayer(proxy: ScrollViewProxy) -> some View {
        let y = max(0, min(sessionBlockY, timelineContentHeight - sessionBlockHeight))
        let sessionWidth: CGFloat = 140
        return sessionBlock
            .frame(width: sessionWidth, height: sessionBlockHeight)
            .position(x: 48 + sessionWidth / 2, y: y + sessionBlockHeight / 2)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation.height
                        startAutoScrollTimer(proxy: proxy)
                    }
                    .onEnded { value in
                        stopAutoScrollTimer()
                        let finalY = timeToY(sessionStart) + value.translation.height
                        let newTime = yToTime(finalY)
                        selectedTime = newTime
                        withAnimation(.easeOut(duration: 0.2)) {
                            dragOffset = 0
                        }
                    }
            )
    }

    private func startAutoScrollTimer(proxy: ScrollViewProxy) {
        guard dragTimer == nil else { return }
        dragTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            scrollToSession(proxy: proxy)
        }
        RunLoop.main.add(dragTimer!, forMode: .common)
    }

    private func stopAutoScrollTimer() {
        dragTimer?.invalidate()
        dragTimer = nil
    }

    private var sessionBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.title3)
                .foregroundStyle(hasConflict ? .white : blockTextOnVolt)
            Text(sessionTitle)
                .font(.caption.bold())
                .foregroundStyle(hasConflict ? .white : blockTextOnVolt)
                .lineLimit(2)
            Spacer()
            Text(timeString(sessionStart))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(hasConflict ? .white.opacity(0.9) : blockTextOnVolt.opacity(0.9))
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    hasConflict
                        ? LinearGradient(colors: [Color.orange, Color.orange.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [pickerVoltColor, pickerVoltColor.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(hasConflict ? Color.white.opacity(0.4) : pickerVoltColor.opacity(0.6), lineWidth: 1)
                )
        )
        .opacity(colorScheme == .dark ? 1 : 0.8)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.15), radius: colorScheme == .dark ? 8 : 12, x: 0, y: 4)
        .shadow(color: pickerVoltColor.opacity(colorScheme == .dark ? 0.5 : 0.3), radius: colorScheme == .dark ? 12 : 15, x: 0, y: colorScheme == .dark ? 2 : 10)
    }

    // MARK: - Helpers

    private func timeToY(_ d: Date) -> CGFloat {
        let h = calendar.component(.hour, from: d)
        let m = calendar.component(.minute, from: d)
        let fraction = CGFloat(h - startHour) + CGFloat(m) / 60.0
        return fraction * hourHeight
    }

    private func yToTime(_ y: CGFloat) -> Date {
        let fraction = max(0, min(Double(y / hourHeight), Double(totalHours)))
        let hour = startHour + Int(fraction)
        let minute = Int((fraction - floor(fraction)) * 60)
        let snappedMinute = (minute / 15) * 15
        return calendar.date(bySettingHour: hour, minute: snappedMinute, second: 0, of: startOfDay) ?? startOfDay
    }

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: d)
    }

    private func scrollToSession(proxy: ScrollViewProxy) {
        let y = max(0, min(sessionBlockY, timelineContentHeight - sessionBlockHeight))
        let hourIndex = min(max(startHour, Int(y / hourHeight) + startHour), endHour - 1)
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo("hour-\(hourIndex)", anchor: .center)
        }
    }
}
