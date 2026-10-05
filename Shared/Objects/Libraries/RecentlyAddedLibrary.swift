//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI

struct RecentlyAddedLibrary: BaseItemKindLibrary {

    let libraryItemTypes: [BaseItemKind] = [.movie, .series]
    let parent: TitledLibraryParent

    /// When this is a group couch, the library shows what's new for everyone
    /// on the couch instead (see `CouchNewForEveryoneLibrary`).
    let couch: CouchGroup?

    init(couch: CouchGroup? = nil) {
        self.couch = couch

        if let couch, couch.isGroup {
            self.parent = CouchNewForEveryoneLibrary(couch: couch).parent
        } else {
            self.parent = .init(displayTitle: L10n.recentlyAdded.localizedCapitalized, id: "recently-added")
        }
    }

    func retrievePage(
        environment: Empty,
        pageState: LibraryPageState
    ) async throws -> [BaseItemDto] {
        if let couch, couch.isGroup {
            return try await CouchNewForEveryoneLibrary(couch: couch).retrievePage(
                environment: environment,
                pageState: pageState
            )
        }

        var parameters = Paths.GetItemsParameters()
        parameters.enableUserData = true
        parameters.fields = PosterSubtitleField.itemFields
        parameters.includeItemTypes = [.movie, .series]
        parameters.isRecursive = true
        parameters.limit = pageState.pageSize
        parameters.sortBy = [.dateCreated]
        parameters.sortOrder = [.descending]
        parameters.startIndex = pageState.pageOffset
        parameters.userID = pageState.userSession.user.id

        let request = Paths.getItems(parameters: parameters)
        let response = try await pageState.userSession.client.send(request)

        return response.value.items ?? []
    }
}
