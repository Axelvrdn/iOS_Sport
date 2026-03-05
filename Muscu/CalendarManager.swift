//
//  CalendarManager.swift
//  Muscu
//
//  Rôle : Singleton EventKit pour synchroniser les séances avec le calendrier Apple (CRUD, événement toute la journée ou horaire, récupération des événements).
//  Utilisé par : PlanningView, SchedulingSheet.
//

import Foundation
import EventKit
import Observation

/// Représentation d’une séance pour la synchro calendrier (titre, repos, durée).
struct PlanningSessionItem {
    let title: String
    let isRestDay: Bool
    /// Durée estimée en minutes (ex: 90 pour 1h30).
    let durationMinutes: Int
}

@MainActor
@Observable
final class CalendarManager {
    static let shared = CalendarManager()
    private let eventStore = EKEventStore()

    /// Préfixe des titres d’événements créés par l’app (pour les retrouver / supprimer).
    private static let eventTitlePrefix = "Muscu – "
    private static let eventNoteMarker = "muscu-app-session"

    var isAuthorized: Bool = false

    private init() {}

    // MARK: - Permissions

    /// Demande l’accès complet au calendrier (`.fullAccess`).
    func requestAccess() async {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            isAuthorized = granted
        } catch {
            print("[CalendarManager] requestFullAccessToEvents error: \(error.localizedDescription)")
            isAuthorized = false
        }
    }

    // MARK: - Sync CRUD

    /// Synchronise la séance avec le calendrier pour la date donnée.
    /// - Returns: L’identifiant de l’événement créé (pour exclure le fantôme en mode modification).
    func syncSessionToCalendar(session: PlanningSessionItem, date: Date, time: Date?) async throws -> String? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)

        // Supprimer tout événement Muscu existant pour ce jour
        let existing = getEvents(for: date).filter { isMuscuEvent($0) }
        for event in existing {
            try? eventStore.remove(event, span: .thisEvent, commit: false)
        }
        try? eventStore.commit()

        if session.isRestDay {
            return nil
        }

        guard let cal = eventStore.defaultCalendarForNewEvents else { return nil }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = cal
        event.title = Self.eventTitlePrefix + session.title
        event.notes = Self.eventNoteMarker

        let duration = max(1, session.durationMinutes)
        if let time = time {
            let start = calendar.date(bySettingHour: calendar.component(.hour, from: time), minute: calendar.component(.minute, from: time), second: 0, of: startOfDay) ?? startOfDay
            event.startDate = start
            event.endDate = calendar.date(byAdding: .minute, value: duration, to: start) ?? start
            event.isAllDay = false
        } else {
            event.startDate = startOfDay
            event.endDate = startOfDay
            event.isAllDay = true
        }

        try eventStore.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }

    /// Indique si l’événement a été créé par l’app.
    private func isMuscuEvent(_ event: EKEvent) -> Bool {
        (event.title?.hasPrefix(Self.eventTitlePrefix) == true) || (event.notes == Self.eventNoteMarker)
    }

    // MARK: - Vérification de disponibilité

    /// Retourne les événements du calendrier par défaut pour la date donnée (toute la journée).
    func getEvents(for date: Date) -> [EKEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return [] }
        guard let cal = eventStore.defaultCalendarForNewEvents else { return [] }

        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: [cal])
        return eventStore.events(matching: predicate)
    }

    /// Événements à afficher sur la timeline (obstacles) : exclut les événements Muscu et optionnellement un ID.
    /// Utilisé pour ne pas afficher le « fantôme » de la séance en cours de modification.
    func getEventsForDisplay(for date: Date, excludingEventID: String? = nil) -> [EKEvent] {
        getEvents(for: date).filter { event in
            if let id = excludingEventID, event.eventIdentifier == id { return false }
            return !isMuscuEvent(event)
        }
    }
}
