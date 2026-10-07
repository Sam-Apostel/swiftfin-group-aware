//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import JellyfinAPI
import Logging
import TVServices

/// Builds the Top Shelf rows and hands them to the Top Shelf extension.
///
/// Rows, in order: what the current couch is in the middle of, what just landed,
/// then every other saved or recent couch and every person on this server, each
/// with what they're in the middle of. Empty rows are left out.
@MainActor
enum TopShelfPublisher {

    private static let logger = Logger.swiftfin()

    private static let maximumSections = 7
    private static let maximumItems = 12

    private static var lastRefresh: Date = .distantPast
    private static var isRefreshing = false

    /// Rebuilds the rows for `session`, at most once a minute unless `force`d.
    static func refresh(session: UserSession, force: Bool = false) async {
        guard !isRefreshing else { return }
        guard force || Date.now.timeIntervalSince(lastRefresh) > 60 else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        let sections = await makeSections(session: session)

        // keep the last rows when everything failed (offline), rather than blanking the shelf
        guard sections.isNotEmpty else { return }

        write(TopShelfSnapshot(sections: sections, createdAt: .now))
        lastRefresh = .now
    }

    /// Falls back to the static Top Shelf image, e.g. after signing out.
    static func clear() {
        guard let url = TopShelfSnapshot.fileURL else { return }

        try? FileManager.default.removeItem(at: url)
        lastRefresh = .distantPast
        TVTopShelfContentProvider.topShelfContentDidChange()
    }

    // MARK: - Sections

    private static func makeSections(session: UserSession) async -> [TopShelfSnapshot.Section] {
        let households = session.householdSessions()
        let sessionsByUserID = Dictionary(households.map { ($0.user.id, $0) }, uniquingKeysWith: { first, _ in first })

        let resumeResults = await CouchHomeSupport.perSession(households) { memberSession in
            try await ResumeItemsLibrary(mediaTypes: [.video]).retrievePage(
                environment: .default,
                pageState: LibraryPageState(pageOffset: 0, pageSize: 24, userSession: memberSession)
            )
        }

        var resumeByUserID: [String: [BaseItemDto]] = [:]

        for (memberSession, items) in zip(households, resumeResults) {
            if let items {
                resumeByUserID[memberSession.user.id] = items
            }
        }

        var sections: [TopShelfSnapshot.Section] = []

        // The current couch (or person) first
        let currentMemberIDs = session.couch.members.map(\.id)
        sections.append(
            continueSection(
                memberIDs: currentMemberIDs,
                session: session,
                sessionsByUserID: sessionsByUserID,
                resumeByUserID: resumeByUserID
            )
        )

        sections.append(await justLandedSection(session: session))

        // Every other couch: saved couches, then recent ones
        var seenCouches: Set<Set<String>> = [Set(currentMemberIDs)]
        let presetStore = Container.shared.couchPresetStore()
        let couchMemberIDs = presetStore.presets(serverID: session.server.id).map(\.memberIDs) + presetStore.recentCouches

        for memberIDs in couchMemberIDs where memberIDs.count > 1 {
            guard seenCouches.insert(Set(memberIDs)).inserted else { continue }

            sections.append(
                continueSection(
                    memberIDs: memberIDs,
                    session: session,
                    sessionsByUserID: sessionsByUserID,
                    resumeByUserID: resumeByUserID
                )
            )
        }

        // Every person on their own
        for memberSession in households {
            guard seenCouches.insert([memberSession.user.id]).inserted else { continue }

            sections.append(
                continueSection(
                    memberIDs: [memberSession.user.id],
                    session: session,
                    sessionsByUserID: sessionsByUserID,
                    resumeByUserID: resumeByUserID
                )
            )
        }

        return Array(sections.filter(\.items.isNotEmpty).prefix(maximumSections))
    }

    /// What everyone in `memberIDs` is in the middle of: the first member's resume items
    /// that every other member also has a resume position in.
    private static func continueSection(
        memberIDs: [String],
        session: UserSession,
        sessionsByUserID: [String: UserSession],
        resumeByUserID: [String: [BaseItemDto]]
    ) -> TopShelfSnapshot.Section {
        let memberSessions = memberIDs.compactMap { sessionsByUserID[$0] }
        let empty = TopShelfSnapshot.Section(title: "", items: [])

        // every member must be signed in and checked, or nothing is known to be "together"
        guard memberSessions.count == memberIDs.count,
              let primary = memberSessions.first,
              let primaryItems = resumeByUserID[primary.user.id]
        else { return empty }

        var togetherIDs = Set(primaryItems.compactMap(\.id))

        for member in memberSessions.dropFirst() {
            guard let items = resumeByUserID[member.user.id] else { return empty }

            togetherIDs.formIntersection(items.compactMap(\.id))
        }

        let items = primaryItems
            .filter { $0.id.map(togetherIDs.contains) ?? false }
            .prefix(maximumItems)
            .compactMap { item in
                makeItem(
                    item,
                    shape: .landscape,
                    session: primary,
                    couchMemberIDs: memberIDs.count > 1 ? memberIDs : nil
                )
            }

        return TopShelfSnapshot.Section(
            title: L10n.TopShelf.continueFor(couchTitle(memberIDs: memberIDs, session: session, sessionsByUserID: sessionsByUserID)),
            items: items
        )
    }

    private static func justLandedSection(session: UserSession) async -> TopShelfSnapshot.Section {
        do {
            let items = try await RecentlyAddedLibrary().retrievePage(
                environment: .default,
                pageState: LibraryPageState(pageOffset: 0, pageSize: maximumItems, userSession: session)
            )

            let currentMemberIDs = session.couch.members.map(\.id)

            return TopShelfSnapshot.Section(
                title: L10n.TopShelf.justLanded,
                items: items.compactMap { item in
                    makeItem(
                        item,
                        shape: .poster,
                        session: session,
                        couchMemberIDs: currentMemberIDs.count > 1 ? currentMemberIDs : nil
                    )
                }
            )
        } catch {
            logger.error("Top Shelf: could not load recently added: \(error.localizedDescription)")
            return TopShelfSnapshot.Section(title: L10n.TopShelf.justLanded, items: [])
        }
    }

    /// A saved couch's name ("🍿 Movie night"), else everyone's names ("Sam & Lisa").
    private static func couchTitle(
        memberIDs: [String],
        session: UserSession,
        sessionsByUserID: [String: UserSession]
    ) -> String {
        if memberIDs.count > 1,
           let preset = Container.shared.couchPresetStore().preset(serverID: session.server.id, memberIDs: Set(memberIDs)),
           preset.name.isNotEmpty
        {
            return [preset.emoji, preset.name].compactMap(\.self).joined(separator: " ")
        }

        let names = memberIDs.compactMap { sessionsByUserID[$0]?.user.username }
        return L10n.Audience.joinedNames(names)
    }

    // MARK: - Items

    private static func makeItem(
        _ item: BaseItemDto,
        shape: TopShelfSnapshot.ImageShape,
        session: UserSession,
        couchMemberIDs: [String]?
    ) -> TopShelfSnapshot.Item? {
        guard let id = item.id else { return nil }

        var link = "swiftfin://\(session.server.id)/\(session.user.id)/item/\(id)"

        if let couchMemberIDs {
            link += "?couch=" + couchMemberIDs.joined(separator: ",")
        }

        guard let linkURL = URL(string: link) else { return nil }

        let title: String = if item.type == .episode, let seriesName = item.seriesName {
            [seriesName, item.episodeLocator].compactMap(\.self).joined(separator: " · ")
        } else {
            item.displayTitle
        }

        let progress = item.userData?.playedPercentage.map { min(max($0 / 100, 0), 1) }

        return TopShelfSnapshot.Item(
            id: id,
            title: title,
            imageURL: imageURL(for: item, shape: shape, session: session),
            imageShape: shape,
            progress: progress,
            link: linkURL
        )
    }

    /// Landscape rows prefer the show's thumb or backdrop over an episode still.
    private static func imageURL(
        for item: BaseItemDto,
        shape: TopShelfSnapshot.ImageShape,
        session: UserSession
    ) -> URL? {
        let candidates: [(ImageType, String?, String?)] = switch shape {
        case .landscape:
            [
                (.thumb, item.id, item.imageTags?[ImageType.thumb.rawValue]),
                (.thumb, item.seriesID, item.seriesThumbImageTag),
                (.thumb, item.parentThumbItemID, item.parentThumbImageTag),
                (.backdrop, item.parentBackdropItemID, item.parentBackdropImageTags?.first),
                (.backdrop, item.id, item.backdropImageTags?.first),
                (.primary, item.id, item.imageTags?[ImageType.primary.rawValue]),
            ]
        case .poster:
            [
                (.primary, item.seriesID, item.seriesPrimaryImageTag),
                (.primary, item.id, item.imageTags?[ImageType.primary.rawValue]),
            ]
        }

        // Top Shelf images: 908 × 512 pt (16:9) and 404 × 608 pt (poster), at 2x
        let maxWidth = shape == .landscape ? 1816 : 808

        for (type, itemID, tag) in candidates {
            guard let itemID, let tag else { continue }

            let request = Paths.getItemImage(
                itemID: itemID,
                imageType: type.rawValue,
                parameters: .init(maxWidth: maxWidth, quality: 90, tag: tag)
            )

            if let url = session.client.url(with: request) {
                return url
            }
        }

        return nil
    }

    // MARK: - Writing

    private static func write(_ snapshot: TopShelfSnapshot) {
        guard let url = TopShelfSnapshot.fileURL else {
            logger.error("Top Shelf: the app group container is unavailable")
            return
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(snapshot).write(to: url, options: .atomic)
            TVTopShelfContentProvider.topShelfContentDidChange()
        } catch {
            logger.error("Top Shelf: could not write the rows: \(error.localizedDescription)")
        }
    }
}
