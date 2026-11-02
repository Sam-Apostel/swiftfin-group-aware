//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// A title from Seerr (a request or a watchlist entry) whose release dates are looked up.
struct ReleaseCalendarCandidate: Hashable, Sendable {

    let mediaType: SeerrMediaType
    let tmdbID: Int
    let title: String?
    let posterPath: String?
    let status: CalendarEntry.Status

    var key: String {
        "\(mediaType.rawValue)-\(tmdbID)"
    }
}

/// When something airs: a whole day, or an exact time.
struct ReleaseMoment: Hashable, Sendable {

    let date: Date
    let isTimeKnown: Bool
}

/// Turns Jellyfin episodes and Seerr release dates into `CalendarEntry`s.
enum ReleaseCalendarBuilder {

    /// How far ahead "Coming up" looks.
    static let daysAhead = 60

    /// Episodes of one season on one day that make it a season drop.
    static let seasonDropMinimumEpisodes = 3

    /// From the start of today to `daysAhead` days later.
    static func window(now: Date = .now) -> DateInterval {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: daysAhead, to: start) ?? start.addingTimeInterval(Double(daysAhead) * 86400)

        return DateInterval(start: start, end: end)
    }

    // MARK: - Dates

    /// The start of a TMDB date (`YYYY-MM-DD`, or ISO 8601 of which only the date is used) in the current time zone.
    static func localDay(fromTMDB string: String?) -> Date? {
        guard let string, string.count >= 10 else { return nil }

        let parts = string.prefix(10)
            .split(separator: "-")
            .compactMap { Int($0) }

        guard parts.count == 3 else { return nil }

        return localDay(year: parts[0], month: parts[1], day: parts[2])
    }

    static func localDay(year: Int?, month: Int?, day: Int?) -> Date? {
        guard let year, let month, let day else { return nil }

        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// Jellyfin stores most premiere dates as midnight UTC: that's a day, not a time.
    static func moment(fromPremiereDate premiereDate: Date) -> ReleaseMoment? {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let components = utc.dateComponents([.year, .month, .day, .hour, .minute], from: premiereDate)

        guard components.hour == 0, components.minute == 0 else {
            return ReleaseMoment(date: premiereDate, isTimeKnown: true)
        }

        return localDay(year: components.year, month: components.month, day: components.day)
            .map { ReleaseMoment(date: $0, isTimeKnown: false) }
    }

    /// `20261105`: the same day key in every time zone.
    static func dayKey(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0

        return String(year * 10000 + month * 100 + day)
    }

    // MARK: - Jellyfin

    /// One entry per episode, or one per season when it drops all at once.
    static func jellyfinEntries(
        from episodes: [BaseItemDto],
        client: JellyfinClient,
        window: DateInterval
    ) -> [CalendarEntry] {
        var order: [String] = []
        var groups: [String: [(episode: BaseItemDto, moment: ReleaseMoment)]] = [:]

        for episode in episodes {
            guard let premiereDate = episode.premiereDate,
                  let release = moment(fromPremiereDate: premiereDate),
                  window.contains(release.date)
            else { continue }

            let seriesKey = episode.seriesID ?? episode.id ?? UUID().uuidString
            let seasonKey = episode.parentIndexNumber.map { String($0) } ?? "-"
            let key = "\(seriesKey)-\(seasonKey)-\(dayKey(release.date))"

            if groups[key] == nil {
                order.append(key)
                groups[key] = []
            }
            groups[key]?.append((episode, release))
        }

        return order.flatMap { key -> [CalendarEntry] in
            let group = groups[key] ?? []

            if group.count >= seasonDropMinimumEpisodes, let first = group.first, let seasonNumber = first.episode.parentIndexNumber {
                let entry = seasonDropEntry(
                    episodes: group.map(\.episode),
                    seasonNumber: seasonNumber,
                    moment: first.moment,
                    client: client
                )
                return [entry].compactMap(\.self)
            }

            return group.compactMap { episodeEntry(episode: $0.episode, moment: $0.moment, client: client) }
        }
    }

    private static func episodeEntry(
        episode: BaseItemDto,
        moment: ReleaseMoment,
        client: JellyfinClient
    ) -> CalendarEntry? {
        guard let episodeID = episode.id else { return nil }

        let isSeriesPremiere = episode.parentIndexNumber == 1 && episode.indexNumber == 1

        return CalendarEntry(
            id: "jf-episode-\(episodeID)",
            kind: isSeriesPremiere ? .seriesPremiere : .episode,
            date: moment.date,
            isTimeKnown: moment.isTimeKnown,
            title: episode.seriesName ?? episode.name ?? "",
            subtitle: episodeLabel(season: episode.parentIndexNumber, episode: episode.indexNumber),
            detail: episode.name,
            imageURL: posterURL(for: episode, client: client),
            destination: .jellyfinItem(id: episode.seriesID ?? episodeID),
            status: episode.locationType == .virtual ? .inLibrarySoon : .inLibrary
        )
    }

    private static func seasonDropEntry(
        episodes: [BaseItemDto],
        seasonNumber: Int,
        moment: ReleaseMoment,
        client: JellyfinClient
    ) -> CalendarEntry? {
        guard let first = episodes.first,
              let destinationID = first.seriesID ?? first.id
        else { return nil }

        let isInLibrary = episodes.allSatisfy { $0.locationType != .virtual }

        return CalendarEntry(
            id: "jf-season-\(destinationID)-s\(seasonNumber)-\(dayKey(moment.date))",
            kind: .seasonDrop,
            date: moment.date,
            isTimeKnown: moment.isTimeKnown,
            title: first.seriesName ?? first.name ?? "",
            subtitle: L10n.ReleaseCalendar.seasonDrop(season: seasonNumber, episodes: episodes.count),
            detail: nil,
            imageURL: posterURL(for: first, client: client),
            destination: .jellyfinItem(id: destinationID),
            status: isInLibrary ? .inLibrary : .inLibrarySoon
        )
    }

    /// The series poster, else the episode's own image.
    private static func posterURL(for episode: BaseItemDto, client: JellyfinClient) -> URL? {
        if let seriesID = episode.seriesID, let tag = episode.seriesPrimaryImageTag {
            return imageURL(itemID: seriesID, tag: tag, client: client)
        }

        guard let episodeID = episode.id,
              let tag = episode.imageTags?[ImageType.primary.rawValue]
        else { return nil }

        return imageURL(itemID: episodeID, tag: tag, client: client)
    }

    private static func imageURL(itemID: String, tag: String, client: JellyfinClient) -> URL? {
        let parameters = Paths.GetItemImageParameters(maxWidth: 300, tag: tag)
        let request = Paths.getItemImage(
            itemID: itemID,
            imageType: ImageType.primary.rawValue,
            parameters: parameters
        )

        return client.url(with: request)
    }

    /// `S2·E5`, or as much of it as is known.
    static func episodeLabel(season: Int?, episode: Int?) -> String {
        switch (season, episode) {
        case let (.some(season), .some(episode)):
            L10n.ReleaseCalendar.episodeNumber(season: season, episode: episode)
        case let (.none, .some(episode)):
            L10n.ReleaseCalendar.episodeOnly(episode)
        default:
            L10n.ReleaseCalendar.newEpisode
        }
    }

    // MARK: - Seerr

    /// The release of a requested or watchlisted title in the window, if any.
    static func seerrEntry(
        candidate: ReleaseCalendarCandidate,
        details: SeerrReleaseDetails,
        season: SeerrReleaseSeason?,
        window: DateInterval
    ) -> CalendarEntry? {
        if details.mediaInfo?.status.isAvailable == true {
            return nil
        }

        switch candidate.mediaType {
        case .movie:
            return movieEntry(candidate: candidate, details: details, window: window)
        case .tv:
            return showEntry(candidate: candidate, details: details, season: season, window: window)
        }
    }

    private static func movieEntry(
        candidate: ReleaseCalendarCandidate,
        details: SeerrReleaseDetails,
        window: DateInterval
    ) -> CalendarEntry? {
        guard let release = movieRelease(details: details, window: window) else { return nil }

        return CalendarEntry(
            id: "seerr-movie-\(candidate.tmdbID)",
            kind: .movie,
            date: release.day,
            isTimeKnown: false,
            title: candidate.title ?? details.title ?? "",
            subtitle: release.label,
            detail: nil,
            imageURL: SeerrImage.url(details.posterPath ?? candidate.posterPath, size: "w342"),
            destination: .seerr(mediaType: .movie, tmdbID: candidate.tmdbID),
            status: candidate.status
        )
    }

    /// Digital first, then physical, then cinemas, in this region (else the US, else anywhere).
    ///
    /// `nil` when the preferred release already happened or nothing falls in the window.
    private static func movieRelease(details: SeerrReleaseDetails, window: DateInterval) -> (day: Date, label: String)? {
        let region = Locale.current.region?.identifier.uppercased() ?? "US"
        let countries = details.releases
        let country = countries.first { $0.countryCode?.uppercased() == region }
            ?? countries.first { $0.countryCode?.uppercased() == "US" }
        let releaseDates = country?.releaseDates ?? countries.flatMap(\.releaseDates)

        let preferredTypes: [SeerrReleaseDate.ReleaseType] = [.digital, .physical, .theatrical]

        for type in preferredTypes {
            let days = releaseDates
                .filter { $0.type == type }
                .compactMap { localDay(fromTMDB: $0.releaseDate) }

            guard let day = days.min() else { continue }
            guard day >= window.start else { return nil }

            if window.contains(day) {
                return (day, movieReleaseLabel(type))
            }
        }

        if releaseDates.isEmpty, let day = localDay(fromTMDB: details.releaseDate), window.contains(day) {
            return (day, L10n.ReleaseCalendar.inCinemas)
        }

        return nil
    }

    private static func movieReleaseLabel(_ type: SeerrReleaseDate.ReleaseType) -> String {
        switch type {
        case .digital:
            L10n.ReleaseCalendar.digital
        case .physical:
            L10n.ReleaseCalendar.onDisc
        case .premiere, .theatricalLimited, .theatrical, .tv:
            L10n.ReleaseCalendar.inCinemas
        }
    }

    private static func showEntry(
        candidate: ReleaseCalendarCandidate,
        details: SeerrReleaseDetails,
        season: SeerrReleaseSeason?,
        window: DateInterval
    ) -> CalendarEntry? {
        let title = candidate.title ?? details.title ?? ""
        let poster = SeerrImage.url(details.posterPath ?? candidate.posterPath, size: "w342")

        if let next = details.nextEpisodeToAir, let day = localDay(fromTMDB: next.airDate), window.contains(day) {
            let sameDayCount = season?.episodes.count(where: { $0.airDate == next.airDate }) ?? 0
            let kind: CalendarEntry.Kind
            let subtitle: String

            if sameDayCount >= seasonDropMinimumEpisodes, let seasonNumber = next.seasonNumber {
                kind = .seasonDrop
                subtitle = L10n.ReleaseCalendar.seasonDrop(season: seasonNumber, episodes: sameDayCount)
            } else if next.seasonNumber == 1, next.episodeNumber == 1 {
                kind = .seriesPremiere
                subtitle = L10n.ReleaseCalendar.seriesPremiere
            } else {
                kind = .episode
                subtitle = episodeLabel(season: next.seasonNumber, episode: next.episodeNumber)
            }

            return CalendarEntry(
                id: "seerr-tv-\(candidate.tmdbID)",
                kind: kind,
                date: day,
                isTimeKnown: false,
                title: title,
                subtitle: subtitle,
                detail: kind == .episode ? next.name : nil,
                imageURL: poster,
                destination: .seerr(mediaType: .tv, tmdbID: candidate.tmdbID),
                status: candidate.status
            )
        }

        guard let day = localDay(fromTMDB: details.firstAirDate), window.contains(day) else { return nil }

        return CalendarEntry(
            id: "seerr-tv-\(candidate.tmdbID)",
            kind: .seriesPremiere,
            date: day,
            isTimeKnown: false,
            title: title,
            subtitle: L10n.ReleaseCalendar.seriesPremiere,
            detail: nil,
            imageURL: poster,
            destination: .seerr(mediaType: .tv, tmdbID: candidate.tmdbID),
            status: candidate.status
        )
    }
}
