//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// The entries of one day of "Coming up".
struct ReleaseCalendarDay: Hashable, Identifiable {

    /// The start of the day.
    let id: Date
    let entries: [CalendarEntry]

    /// "Today", "Tomorrow", a weekday this week, then "Monday 16 November".
    var title: String {
        Self.title(for: id)
    }

    static func title(for day: Date, now: Date = .now) -> String {
        let calendar = Calendar.current

        if calendar.isDate(day, inSameDayAs: now) {
            return L10n.ReleaseCalendar.today
        }

        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: day)).day ?? 0

        if days == 1 {
            return L10n.ReleaseCalendar.tomorrow
        }

        if days > 1, days < 7 {
            return day.formatted(.dateTime.weekday(.wide))
        }

        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    /// `entries` are sorted by date, so are the days.
    static func group(_ entries: [CalendarEntry]) -> [ReleaseCalendarDay] {
        let calendar = Calendar.current
        var order: [Date] = []
        var grouped: [Date: [CalendarEntry]] = [:]

        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)

            if grouped[day] == nil {
                order.append(day)
                grouped[day] = []
            }
            grouped[day]?.append(entry)
        }

        return order.map { ReleaseCalendarDay(id: $0, entries: grouped[$0] ?? []) }
    }
}
