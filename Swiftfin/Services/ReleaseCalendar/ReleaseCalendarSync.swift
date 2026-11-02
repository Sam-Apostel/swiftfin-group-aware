//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import EventKit
import FactoryKit
import Foundation
import Logging
import SwiftUI
import UIKit

extension Container {

    var releaseCalendarSync: Factory<ReleaseCalendarSync> {
        self { @MainActor in ReleaseCalendarSync() }
            .singleton
    }
}

enum ReleaseCalendarSyncError: LocalizedError {

    case accessDenied
    case calendarUnavailable

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            L10n.ReleaseCalendar.calendarAccessDenied
        case .calendarUnavailable:
            L10n.ReleaseCalendar.calendarUnavailable
        }
    }
}

/// Keeps a "Couchfin" calendar on this iPhone with what's coming up.
///
/// Every `CalendarEntry` becomes one event, keyed by its id in the event URL
/// (`couchfin://calendar/<id>`, with the event identifiers in `Defaults` as a fallback).
/// Syncs when turned on, and when the app becomes active or the person changes,
/// at most every `minimumInterval`. Turning it off removes the calendar.
@MainActor
final class ReleaseCalendarSync: ObservableObject {

    @Published
    private(set) var isEnabled: Bool
    @Published
    private(set) var isSyncing: Bool = false

    private let eventStore = EKEventStore()
    private let logger = Logger.swiftfin()

    private var cancellables: Set<AnyCancellable> = []
    private var syncTask: Task<Void, Never>?

    private static let minimumInterval: TimeInterval = 6 * 60 * 60
    private static let eventURLPrefix = "couchfin://calendar/"
    private static let timedEventDuration: TimeInterval = 60 * 60

    init() {
        self.isEnabled = Defaults[.ReleaseCalendar.syncToCalendar]
    }

    /// Syncs whenever the app becomes active and when the person changes.
    func start() {
        guard cancellables.isEmpty else { return }

        NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.syncIfNeeded()
                }
            }
            .store(in: &cancellables)

        Container.shared
            .userSessionManager()
            .$currentSession
            .map { [$0?.server.id, $0?.user.id] }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.syncIfNeeded()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - On / off

    /// Turning on asks for full calendar access, creates the calendar and syncs.
    ///
    /// - Throws: `ReleaseCalendarSyncError` when access is denied or the calendar can't be created.
    func setEnabled(_ enabled: Bool) async throws {
        guard enabled else {
            disable()
            return
        }
        guard try await requestAccess() else {
            throw ReleaseCalendarSyncError.accessDenied
        }

        _ = try couchfinCalendar()

        Defaults[.ReleaseCalendar.syncToCalendar] = true
        isEnabled = true

        await sync()
    }

    private func requestAccess() async throws -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)

        if status == .notDetermined {
            return try await eventStore.requestFullAccessToEvents()
        }

        return status == .fullAccess
    }

    private var hasFullAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    private func disable() {
        syncTask?.cancel()

        Defaults[.ReleaseCalendar.syncToCalendar] = false
        isEnabled = false

        if hasFullAccess,
           let identifier = Defaults[.ReleaseCalendar.calendarIdentifier],
           let calendar = eventStore.calendar(withIdentifier: identifier)
        {
            do {
                try eventStore.removeCalendar(calendar, commit: true)
            } catch {
                logger.error(
                    "Coming up: couldn't remove the calendar",
                    metadata: ["error": .string(error.localizedDescription)]
                )
            }
        }

        Defaults[.ReleaseCalendar.calendarIdentifier] = nil
        Defaults[.ReleaseCalendar.eventIdentifiers] = [:]
        Defaults[.ReleaseCalendar.lastSyncDate] = .distantPast
    }

    // MARK: - Calendar

    /// The saved calendar, a writable one named "Couchfin", or a new one.
    private func couchfinCalendar() throws -> EKCalendar {
        if let identifier = Defaults[.ReleaseCalendar.calendarIdentifier],
           let calendar = eventStore.calendar(withIdentifier: identifier),
           calendar.allowsContentModifications
        {
            return calendar
        }

        let existing = eventStore.calendars(for: .event)
            .first { $0.title == L10n.Couchfin.appName && $0.allowsContentModifications }

        if let existing {
            Defaults[.ReleaseCalendar.calendarIdentifier] = existing.calendarIdentifier
            return existing
        }

        guard let source = preferredSource() else {
            throw ReleaseCalendarSyncError.calendarUnavailable
        }

        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = L10n.Couchfin.appName
        calendar.source = source
        calendar.cgColor = UIColor(Color.Couchfin.accent).cgColor

        do {
            try eventStore.saveCalendar(calendar, commit: true)
        } catch {
            logger.error(
                "Coming up: couldn't create the calendar",
                metadata: ["error": .string(error.localizedDescription)]
            )
            throw ReleaseCalendarSyncError.calendarUnavailable
        }

        Defaults[.ReleaseCalendar.calendarIdentifier] = calendar.calendarIdentifier
        return calendar
    }

    /// iCloud, else where new events go by default, else on this iPhone.
    private func preferredSource() -> EKSource? {
        let sources = eventStore.sources

        if let iCloud = sources.first(where: { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("icloud") }) {
            return iCloud
        }

        if let source = eventStore.defaultCalendarForNewEvents?.source {
            return source
        }

        return sources.first { $0.sourceType == .local }
    }

    // MARK: - Sync

    /// Syncs when on and the last sync is older than `minimumInterval`.
    func syncIfNeeded() async {
        guard isEnabled, Date.now.timeIntervalSince(Defaults[.ReleaseCalendar.lastSyncDate]) > Self.minimumInterval else { return }

        await sync()
    }

    /// Brings the calendar up to date. Concurrent calls share one sync.
    func sync() async {
        if let syncTask {
            await syncTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            await self.performSync()
        }
        syncTask = task
        isSyncing = true

        await task.value

        syncTask = nil
        isSyncing = false
    }

    private func performSync() async {
        guard isEnabled, hasFullAccess, Container.shared.currentUserSession() != nil else { return }

        let service = Container.shared.releaseCalendarService()
        await service.refresh()

        // Never empty the calendar because a server couldn't be reached
        guard service.lastLoadWasComplete, isEnabled, !Task.isCancelled else { return }

        do {
            let calendar = try couchfinCalendar()
            try apply(service.entries, to: calendar)
            Defaults[.ReleaseCalendar.lastSyncDate] = .now
        } catch {
            logger.error(
                "Coming up: calendar sync failed",
                metadata: ["error": .string(error.localizedDescription)]
            )
        }
    }

    /// Adds, updates and removes events so the calendar matches `entries`. Past events are kept.
    private func apply(_ entries: [CalendarEntry], to calendar: EKCalendar) throws {
        let window = ReleaseCalendarBuilder.window()
        let predicate = eventStore.predicateForEvents(
            withStart: window.start.addingTimeInterval(-86400),
            end: window.end.addingTimeInterval(2 * 86400),
            calendars: [calendar]
        )

        let keysByIdentifier = Dictionary(
            Defaults[.ReleaseCalendar.eventIdentifiers].map { ($0.value, $0.key) },
            uniquingKeysWith: { first, _ in first }
        )

        var existing: [String: EKEvent] = [:]

        for event in eventStore.events(matching: predicate) {
            let identifierKey = event.eventIdentifier.flatMap { keysByIdentifier[$0] }

            guard let key = Self.key(of: event) ?? identifierKey else { continue }

            if existing[key] != nil {
                try eventStore.remove(event, span: .thisEvent, commit: false)
            } else {
                existing[key] = event
            }
        }

        var saved: [(key: String, event: EKEvent)] = []

        for entry in entries {
            let event = existing.removeValue(forKey: entry.id) ?? EKEvent(eventStore: eventStore)

            if update(event, with: entry, calendar: calendar) {
                try eventStore.save(event, span: .thisEvent, commit: false)
            }

            saved.append((entry.id, event))
        }

        for event in existing.values where event.startDate >= window.start {
            try eventStore.remove(event, span: .thisEvent, commit: false)
        }

        try eventStore.commit()

        var identifiers: [String: String] = [:]

        for (key, event) in saved {
            if let identifier = event.eventIdentifier {
                identifiers[key] = identifier
            }
        }

        Defaults[.ReleaseCalendar.eventIdentifiers] = identifiers
    }

    /// Updates `event` from `entry`. Returns whether anything changed.
    private func update(_ event: EKEvent, with entry: CalendarEntry, calendar: EKCalendar) -> Bool {
        let url = URL(string: Self.eventURLPrefix + entry.id)
        let isAllDay = !entry.isTimeKnown
        let endDate = isAllDay ? entry.date : entry.date.addingTimeInterval(Self.timedEventDuration)
        let notes = [entry.detail, entry.statusTitle]
            .compactMap(\.self)
            .joined(separator: "\n")

        let isSameDate = if isAllDay {
            event.isAllDay && event.startDate.map { Calendar.current.isDate($0, inSameDayAs: entry.date) } == true
        } else {
            !event.isAllDay && event.startDate == entry.date && event.endDate == endDate
        }

        let isUnchanged = isSameDate
            && event.calendar?.calendarIdentifier == calendar.calendarIdentifier
            && event.title == entry.eventTitle
            && event.notes == notes
            && event.url == url

        guard !isUnchanged else { return false }

        event.calendar = calendar
        event.title = entry.eventTitle
        event.isAllDay = isAllDay
        event.startDate = entry.date
        event.endDate = endDate
        event.notes = notes
        event.url = url

        return true
    }

    private static func key(of event: EKEvent) -> String? {
        guard let url = event.url?.absoluteString, url.hasPrefix(eventURLPrefix) else { return nil }

        return String(url.dropFirst(eventURLPrefix.count))
    }
}
