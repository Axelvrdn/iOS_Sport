//
//  SchedulingSheet.swift
//  Muscu
//
//  Rôle : Sheet de planification d’une séance (choix de l’heure, affichage des événements du jour, détection de conflit).
//  Utilisé par : PlanningView (bouton « Planifier l’heure »).
//

import SwiftUI
import EventKit

struct SchedulingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var calendarManager = CalendarManager.shared

    let date: Date
    let sessionTitle: String
    let durationMinutes: Int
    let initialDate: Date?
    let excludedEventID: String?
    /// (heure choisie, identifiant événement calendrier créé/mis à jour)
    let onConfirm: (Date?, String?) -> Void

    @State private var selectedTime: Date
    @State private var dayEvents: [EKEvent] = []
    @State private var isSyncing = false
    @State private var errorMessage: String?

    private let calendar = Calendar.current

    init(date: Date, sessionTitle: String, durationMinutes: Int = 90, initialDate: Date? = nil, excludedEventID: String? = nil, onConfirm: @escaping (Date?, String?) -> Void) {
        self.date = date
        self.sessionTitle = sessionTitle
        self.durationMinutes = durationMinutes
        self.initialDate = initialDate
        self.excludedEventID = excludedEventID
        self.onConfirm = onConfirm
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        let defaultTime: Date
        if let initial = initialDate, cal.isDate(initial, inSameDayAs: date) {
            defaultTime = initial
        } else {
            defaultTime = cal.date(bySettingHour: 19, minute: 0, second: 0, of: startOfDay) ?? startOfDay
        }
        _selectedTime = State(initialValue: defaultTime)
    }

    private var sessionStart: Date {
        calendar.date(bySettingHour: calendar.component(.hour, from: selectedTime), minute: calendar.component(.minute, from: selectedTime), second: 0, of: calendar.startOfDay(for: date)) ?? selectedTime
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VisualTimePickerView(
                    selectedTime: $selectedTime,
                    date: date,
                    durationMinutes: durationMinutes,
                    dayEvents: dayEvents,
                    sessionTitle: sessionTitle,
                    initialDate: initialDate,
                    excludedEventID: excludedEventID
                )

                if let msg = errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                // Bouton Confirmer fixe en bas
                Button {
                    confirmTapped()
                } label: {
                    HStack {
                        if isSyncing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Text("Confirmer")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isSyncing)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("Planifier l'heure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
            }
            .task {
                await calendarManager.requestAccess()
                reloadEvents()
            }
            .onChange(of: selectedTime) { _, _ in
                reloadEvents()
            }
        }
    }

    private func eventColor(_ event: EKEvent) -> Color {
        event.calendar?.cgColor.flatMap { Color(cgColor: $0) } ?? .blue
    }

    private func timeRange(_ event: EKEvent) -> String {
        guard let start = event.startDate, let end = event.endDate else { return "" }
        let f = DateFormatter()
        f.timeStyle = .short
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }

    private func reloadEvents() {
        dayEvents = calendarManager.getEventsForDisplay(for: date, excludingEventID: excludedEventID)
    }

    private func confirmTapped() {
        isSyncing = true
        errorMessage = nil
        let session = PlanningSessionItem(title: sessionTitle, isRestDay: false, durationMinutes: durationMinutes)
        Task {
            do {
                let eventID = try await calendarManager.syncSessionToCalendar(session: session, date: date, time: selectedTime)
                await MainActor.run {
                    onConfirm(selectedTime, eventID)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
            await MainActor.run {
                isSyncing = false
            }
        }
    }
}
