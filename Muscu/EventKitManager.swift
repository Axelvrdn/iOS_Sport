//
//  EventKitManager.swift
//  Muscu
//
//  Singleton manager for EventKit integration (calendar sync)
//

import Foundation
import Combine
import EventKit

@MainActor
final class EventKitManager: ObservableObject {
    static let shared = EventKitManager()
    private let eventStore = EKEventStore()

    @Published var isAuthorized: Bool = false

    private init() {}

    // MARK: - Authorization

    func requestAccess() async {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            isAuthorized = granted
        } catch {
            print("EventKit authorization error: \(error.localizedDescription)")
            isAuthorized = false
        }
    }

    // MARK: - Helpers

    private func defaultCalendar() -> EKCalendar? {
        eventStore.defaultCalendarForNewEvents
    }

    // MARK: - CRUD pour les séances

    func createWorkoutEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        notes: String? = nil
    ) async throws -> EKEvent? {
        guard let calendar = defaultCalendar() else { return nil }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.notes = notes

        try eventStore.save(event, span: .thisEvent, commit: true)
        return event
    }

    func fetchWorkoutEvents(
        from startDate: Date,
        to endDate: Date
    ) -> [EKEvent] {
        guard let calendar = defaultCalendar() else { return [] }

        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: [calendar]
        )

        let events = eventStore.events(matching: predicate)
        // Plus tard, on pourra filtrer sur un tag dans `notes` ou `title`
        return events
    }

    func updateEvent(
        _ event: EKEvent,
        newStartDate: Date,
        newEndDate: Date
    ) throws {
        event.startDate = newStartDate
        event.endDate = newEndDate
        try eventStore.save(event, span: .thisEvent, commit: true)
    }

    func deleteEvent(_ event: EKEvent) throws {
        try eventStore.remove(event, span: .thisEvent, commit: true)
    }
}
