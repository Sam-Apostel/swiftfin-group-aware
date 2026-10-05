//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI

struct ResumeItemsLibrary: BaseItemKindLibrary {

    let mediaTypes: [MediaType]
    let parent: TitledLibraryParent

    /// When this is a group couch, the library shows what the whole couch
    /// is in the middle of instead (see `CouchResumeLibrary`).
    let couch: CouchGroup?

    var libraryItemTypes: [BaseItemKind] {
        mediaTypes.flatMap(\.supportedLibraryItemTypes)
    }

    /// - Parameter title: Replaces the row title "Continue", e.g. "Sam's Continue Watching" on a group's home.
    init(
        mediaTypes: [MediaType] = [.video],
        couch: CouchGroup? = nil,
        title: String? = nil
    ) {
        self.mediaTypes = mediaTypes
        self.couch = couch

        if let couch, couch.isGroup {
            self.parent = CouchResumeLibrary(couch: couch).parent
        } else {
            self.parent = .init(displayTitle: title ?? L10n.continue, id: "continue-watching")
        }
    }

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        if let couch, couch.isGroup {
            return try await CouchResumeLibrary(couch: couch).retrievePage(
                environment: environment,
                pageState: pageState
            )
        }

        var parameters = Paths.GetResumeItemsParameters()
        parameters.enableUserData = true
        parameters.fields = PosterSubtitleField.itemFields
        parameters.limit = pageState.pageSize
        parameters.mediaTypes = mediaTypes
        parameters.startIndex = pageState.pageOffset
        parameters.userID = pageState.userSession.user.id

        let request = Paths.getResumeItems(parameters: parameters)
        let response = try await pageState.userSession.client.send(request)

        return response.value.items ?? []
    }

    func onItemUserDataChanged(
        viewModel: PagingLibraryViewModel<ResumeItemsLibrary>,
        userData: UserItemDataDto
    ) {
        guard let itemID = userData.itemID else { return }

        if userData.isPlayed == true {
            viewModel.elements.removeAll { $0.id == itemID }
            return
        }

        let isAlreadyLoaded = viewModel.elements.contains { $0.id == itemID }
        guard !isAlreadyLoaded else { return }
        guard (userData.playbackPositionTicks ?? 0) > 0 else { return }

        viewModel.scheduleRefreshForItemUserData(minimumInterval: 30)
    }
}

private extension MediaType {

    var supportedLibraryItemTypes: [BaseItemKind] {
        switch self {
        case .audio:
            [.audio, .musicAlbum]
        case .video:
            [.episode, .movie, .video]
        case .book:
            [.book]
        case .photo:
            [.photo]
        case .unknown:
            []
        }
    }
}
