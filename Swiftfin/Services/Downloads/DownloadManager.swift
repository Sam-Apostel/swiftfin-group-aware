//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import FactoryKit
import Foundation
import JellyfinAPI
import Logging

extension Container {

    var downloadManager: Factory<DownloadManager> {
        self { @MainActor in DownloadManager() }
            .singleton
    }
}

/// Downloads items to the device for offline playback.
///
/// Downloads run in a background `URLSession`, so they continue while the
/// app is suspended. Each download lives in its own folder:
///
/// ```
/// Application Support/Downloads/<item id>/
///     record.json
///     media.<container>
///     poster.jpg
/// ```
@MainActor
final class DownloadManager: NSObject, ObservableObject {

    static let sessionIdentifier = "\(Bundle.main.bundleIdentifier ?? "org.jellyfin.swiftfin").downloads"

    private static let recordFileName = "record.json"
    private static let resumeDataFileName = "resume.data"

    /// All downloads, keyed by item ID.
    @Published
    private(set) var records: [String: DownloadRecord] = [:]

    /// Set by the app delegate when the system relaunches the app for background download events.
    var backgroundCompletionHandler: (() -> Void)?

    private let logger = Logger.swiftfin()
    private let rootDirectory: URL
    private let launchDate = Date.now

    /// Item IDs that are being prepared, before a record exists.
    private var preparingIDs: Set<String> = []
    private var lastProgressUpdate: [String: (date: Date, bytes: Int64)] = [:]
    /// Smoothed download speed of each running download, in bytes per second.
    private(set) var speeds: [String: Double] = [:]
    /// The current task of each download, so callbacks from a cancelled task are ignored.
    private var tasks: [String: URLSessionTask] = [:]
    private var cancellables: Set<AnyCancellable> = []
    /// Whether running tasks of a previous launch have been matched to records.
    private var hasReconnectedTasks = false

    /// Downloads run one at a time, in the order they were added, so episodes finish in order.
    private static let maximumActiveDownloads = 1

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.allowsCellularAccess = true
        // Keeps tasks released for the background in order
        configuration.httpMaximumConnectionsPerHost = 1

        return URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: .main
        )
    }()

    override init() {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        rootDirectory = applicationSupport.appending(path: "Downloads", directoryHint: .isDirectory)

        super.init()

        prepareRootDirectory()
        loadRecords()
        reconnectTasks()

        Notifications[.applicationWillEnterForeground]
            .publisher
            .sink { [weak self] _ in
                Task { await self?.syncPlaybackProgress() }
            }
            .store(in: &cancellables)

        // Tasks created while the app is in the background may be delayed by the system,
        // so hand every queued download to the session before the app leaves the foreground.
        Notifications[.applicationWillResignActive]
            .publisher
            .sink { [weak self] _ in self?.startQueuedDownloads(limit: nil) }
            .store(in: &cancellables)
    }

    // MARK: - Queries

    func record(for itemID: String?) -> DownloadRecord? {
        guard let itemID, let record = records[itemID], isVisible(record) else { return nil }

        return record
    }

    /// The downloads of the signed-in user on the current server.
    var currentRecords: [DownloadRecord] {
        records.values.filter { isVisible($0) }
    }

    private func isVisible(_ record: DownloadRecord) -> Bool {
        guard let userSession = Container.shared.currentUserSession() else { return false }

        return record.userID == userSession.user.id && record.serverID == userSession.server.id
    }

    func isPreparing(_ itemID: String?) -> Bool {
        guard let itemID else { return false }

        return preparingIDs.contains(itemID)
    }

    static func canDownload(_ item: BaseItemDto) -> Bool {
        guard Container.shared.currentUserSession()?.user.data.policy?.enableContentDownloading == true else { return false }

        return switch item.type {
        case .movie, .episode, .video, .musicVideo, .season, .series:
            !item.isLiveStream
        default:
            false
        }
    }

    /// The local file of a completed download.
    func mediaURL(for record: DownloadRecord) -> URL? {
        guard record.status == .completed, let mediaFileName = record.mediaFileName else { return nil }

        let url = directory(for: record.id).appending(path: mediaFileName)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    func imageURL(for record: DownloadRecord) -> URL? {
        guard let imageFileName = record.imageFileName else { return nil }

        return directory(for: record.id).appending(path: imageFileName)
    }

    /// Bytes used by the current user's downloads on disk, including downloads in progress.
    var totalBytesUsed: Int64 {
        currentRecords.reduce(0) { $0 + $1.bytesWritten }
    }

    /// Estimated time until a running download finishes.
    func timeRemaining(for record: DownloadRecord) -> Duration? {
        guard record.status == .downloading,
              let speed = speeds[record.id], speed > 0,
              let expected = record.bytesExpected, expected > record.bytesWritten
        else { return nil }

        return .seconds(Double(expected - record.bytesWritten) / speed)
    }

    // MARK: - Starting downloads

    /// Downloads a single playable item, or every episode of a season.
    func download(
        _ item: BaseItemDto,
        quality: DownloadQuality,
        onlyUnplayed: Bool = false
    ) async throws {
        switch item.type {
        case .season, .series:
            let seasonEpisodes = try await episodes(for: item, onlyUnplayed: onlyUnplayed)

            for episode in seasonEpisodes {
                try await downloadPlayable(episode, quality: quality)
            }

        default:
            try await downloadPlayable(item, quality: quality)
        }
    }

    /// The episodes that downloading a season or series would include.
    func episodes(for item: BaseItemDto, onlyUnplayed: Bool) async throws -> [BaseItemDto] {
        let userSession = try requireUserSession()

        guard let id = item.id else { throw ErrorMessage(L10n.unknownError) }

        let seriesID = item.type == .series ? id : (item.seriesID ?? id)

        var parameters = Paths.GetEpisodesParameters()
        parameters.enableUserData = true
        parameters.fields = [.mediaSources]
        parameters.isMissing = false
        parameters.userID = userSession.user.id

        if item.type == .season {
            parameters.seasonID = id
        }

        let request = Paths.getEpisodes(seriesID: seriesID, parameters: parameters)
        let response = try await userSession.client.send(request)
        let episodes = response.value.items ?? []

        guard onlyUnplayed else { return episodes }

        return episodes.filter { $0.userData?.isPlayed != true }
    }

    private func downloadPlayable(_ item: BaseItemDto, quality: DownloadQuality) async throws {
        guard let itemID = item.id else { throw ErrorMessage(L10n.unknownError) }

        if let existing = records[itemID], existing.status != .failed {
            return
        }

        guard !preparingIDs.contains(itemID) else { return }

        preparingIDs.insert(itemID)
        objectWillChange.send()
        defer {
            preparingIDs.remove(itemID)
            objectWillChange.send()
        }

        let userSession = try requireUserSession()
        let fullItem = try await item.getFullItem(userSession: userSession)

        guard let sourceMediaSource = fullItem.mediaSources?.first else {
            throw ErrorMessage(L10n.Downloads.noMedia)
        }

        let request = try Self.makeRequest(
            item: fullItem,
            mediaSource: sourceMediaSource,
            quality: quality,
            client: userSession.client
        )

        let folder = directory(for: itemID)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let estimatedSize = quality.estimatedSize(
            runtimeSeconds: fullItem.runtime?.seconds ?? 0,
            sourceSize: sourceMediaSource.size,
            sourceBitrate: sourceMediaSource.bitrate
        )

        var record = DownloadRecord(
            id: itemID,
            serverID: userSession.server.id,
            userID: userSession.user.id,
            item: fullItem,
            mediaSource: Self.offlineMediaSource(from: sourceMediaSource, quality: quality),
            quality: quality,
            status: .queued,
            bytesExpected: estimatedSize.map { Int64($0) },
            dateAdded: .now
        )

        record.downloadURL = request.url
        record.mediaFileName = "media.\(Self.fileExtension(for: sourceMediaSource, quality: quality))"

        update(record)
        startQueuedDownloads()

        await downloadImage(for: fullItem, client: userSession.client)
    }

    // MARK: - Managing downloads

    func retry(_ record: DownloadRecord) async throws {
        let resumeDataURL = directory(for: record.id).appending(path: Self.resumeDataFileName)

        let canResume = !record.quality.isTranscoded && FileManager.default.fileExists(atPath: resumeDataURL.path(percentEncoded: false))

        if canResume || record.downloadURL != nil {
            var record = record
            record.status = .queued
            record.errorMessage = nil
            update(record)
            startQueuedDownloads()
            return
        }

        try await downloadPlayable(record.item, quality: record.quality)
    }

    func delete(_ record: DownloadRecord) {
        if let task = tasks.removeValue(forKey: record.id) {
            task.cancel()
        } else {
            cancelUntrackedTasks(for: record.id)
        }

        try? FileManager.default.removeItem(at: directory(for: record.id))
        records[record.id] = nil
        lastProgressUpdate[record.id] = nil
        speeds[record.id] = nil

        startQueuedDownloads()
    }

    func deleteAll() {
        for record in currentRecords {
            delete(record)
        }
    }

    // MARK: - Offline progress

    func savePlaybackProgress(itemID: String, position: Duration, runtime: Duration?) {
        guard var record = records[itemID] else { return }

        // Treat the last 10% as watched, like the server does by default
        if let runtime, runtime > .zero, position.seconds / runtime.seconds >= 0.9 {
            record.isPlayed = true
            record.playbackPositionTicks = 0
        } else {
            // Leave the played state as it is on the server
            record.isPlayed = nil
            record.playbackPositionTicks = position.ticks
        }

        record.hasPendingProgressSync = true
        update(record)
    }

    /// Sends playback progress made offline to the server, when it can be reached.
    func syncPlaybackProgress() async {
        guard let userSession = Container.shared.currentUserSession() else { return }

        let pending = records.values.filter {
            $0.hasPendingProgressSync
                && $0.userID == userSession.user.id
                && $0.serverID == userSession.server.id
        }

        for record in pending {
            var body = UpdateUserItemDataDto()
            body.playbackPositionTicks = record.playbackPositionTicks
            body.isPlayed = record.isPlayed

            do {
                let request = Paths.updateItemUserData(itemID: record.id, userID: record.userID, body)
                _ = try await userSession.client.send(request)

                guard var current = records[record.id] else { continue }

                current.hasPendingProgressSync = false
                update(current)
            } catch {
                // Most likely still offline, try again later
                logger.debug("Unable to sync offline playback progress: \(error.localizedDescription)")
                return
            }
        }
    }

    // MARK: - Requests

    private static func makeRequest(
        item: BaseItemDto,
        mediaSource: MediaSourceInfo,
        quality: DownloadQuality,
        client: JellyfinClient
    ) throws -> URLRequest {
        guard let itemID = item.id else { throw ErrorMessage(L10n.unknownError) }

        let url = if quality.isTranscoded {
            transcodedURL(itemID: itemID, mediaSource: mediaSource, quality: quality, client: client)
        } else {
            originalURL(itemID: itemID, item: item, mediaSource: mediaSource, client: client)
        }

        guard let url else { throw ErrorMessage(L10n.unknownError) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        return request
    }

    private static func originalURL(
        itemID: String,
        item: BaseItemDto,
        mediaSource: MediaSourceInfo,
        client: JellyfinClient
    ) -> URL? {
        let parameters = Paths.GetVideoStreamParameters(
            isStatic: true,
            tag: mediaSource.eTag ?? item.etag,
            mediaSourceID: mediaSource.id ?? itemID
        )

        let request = Paths.getVideoStream(itemID: itemID, parameters: parameters)
        return client.url(with: request, queryAPIKey: true)
    }

    private static func transcodedURL(
        itemID: String,
        mediaSource: MediaSourceInfo,
        quality: DownloadQuality,
        client: JellyfinClient
    ) -> URL? {
        var parameters = Paths.GetVideoStreamByContainerParameters()
        parameters.isStatic = false
        parameters.mediaSourceID = mediaSource.id ?? itemID
        parameters.deviceID = client.configuration.deviceID
        parameters.playSessionID = UUID().uuidString
        parameters.context = .static
        parameters.videoCodec = "h264"
        parameters.audioCodec = "aac"
        parameters.maxAudioChannels = 2
        parameters.audioBitRate = DownloadQuality.audioBitrate
        parameters.videoBitRate = quality.videoBitrate
        parameters.maxWidth = quality.maxWidth
        parameters.audioStreamIndex = mediaSource.defaultAudioStreamIndex

        // Burn in the subtitle the server would pick by default,
        // e.g. forced or preferred-language subtitles
        if let subtitleIndex = mediaSource.defaultSubtitleStreamIndex, subtitleIndex >= 0 {
            parameters.subtitleStreamIndex = subtitleIndex
            parameters.subtitleMethod = .encode
        }

        let request = Paths.getVideoStreamByContainer(
            itemID: itemID,
            container: "mp4",
            parameters: parameters
        )
        return client.url(with: request, queryAPIKey: true)
    }

    private static func fileExtension(for mediaSource: MediaSourceInfo, quality: DownloadQuality) -> String {
        guard !quality.isTranscoded else { return "mp4" }

        // Containers can be reported as a list, e.g. "mov,mp4,m4a"
        let container = mediaSource.container?
            .split(separator: ",")
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces) }

        guard let container, container.isNotEmpty else { return "mkv" }

        return container
    }

    /// The media source as it will be in the downloaded file.
    private static func offlineMediaSource(from mediaSource: MediaSourceInfo, quality: DownloadQuality) -> MediaSourceInfo {
        var mediaSource = mediaSource
        let streams = mediaSource.mediaStreams ?? []

        mediaSource.transcodingURL = nil
        mediaSource.transcodingContainer = nil
        mediaSource.transcodingSubProtocol = nil

        if quality.isTranscoded {
            let audioIndex = mediaSource.defaultAudioStreamIndex
                ?? streams.first(where: { $0.type == .audio })?.index

            let video = streams.first(where: { $0.type == .video })
            let audio = streams.first(where: { $0.type == .audio && $0.index == audioIndex })

            mediaSource.mediaStreams = [video, audio].compactMap(\.self)
            mediaSource.container = "mp4"
            mediaSource.defaultAudioStreamIndex = audio?.index
            mediaSource.defaultSubtitleStreamIndex = -1
            mediaSource.size = nil
            mediaSource.bitrate = nil
        } else {
            // External subtitles are separate files on the server, they won't be in the download
            mediaSource.mediaStreams = streams.filter { !($0.type == .subtitle && $0.isExternal == true) }

            if let defaultSubtitle = mediaSource.defaultSubtitleStreamIndex,
               !(mediaSource.mediaStreams ?? []).contains(where: { $0.index == defaultSubtitle })
            {
                mediaSource.defaultSubtitleStreamIndex = -1
            }
        }

        return mediaSource
    }

    private func downloadImage(for item: BaseItemDto, client: JellyfinClient) async {
        guard let itemID = item.id else { return }

        let parameters = Paths.GetItemImageParameters(maxWidth: 600, quality: 90)
        let request = Paths.getItemImage(itemID: itemID, imageType: ImageType.primary.rawValue, parameters: parameters)

        guard let url = client.url(with: request) else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard (response as? HTTPURLResponse)?.statusCode == 200, data.isNotEmpty else { return }

            let fileName = "poster.jpg"
            try data.write(to: directory(for: itemID).appending(path: fileName))

            guard var record = records[itemID] else { return }

            record.imageFileName = fileName
            update(record)
        } catch {
            logger.debug("Unable to download image for \(itemID): \(error.localizedDescription)")
        }
    }

    // MARK: - Persistence

    private func requireUserSession() throws -> UserSession {
        guard let userSession = Container.shared.currentUserSession() else {
            throw UserSessionError.missingCurrentSession
        }

        return userSession
    }

    private func directory(for itemID: String) -> URL {
        let safeID = itemID.replacing("/", with: "_")
        return rootDirectory.appending(path: safeID, directoryHint: .isDirectory)
    }

    private func prepareRootDirectory() {
        do {
            try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

            // Downloads can be large and can be downloaded again, don't back them up
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var rootDirectory = rootDirectory
            try rootDirectory.setResourceValues(values)
        } catch {
            logger.error("Unable to create downloads directory: \(error.localizedDescription)")
        }
    }

    private func loadRecords() {
        let decoder = JSONDecoder()

        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        var loaded: [String: DownloadRecord] = [:]

        for folder in folders {
            let recordURL = folder.appending(path: Self.recordFileName)

            guard let data = try? Data(contentsOf: recordURL),
                  let record = try? decoder.decode(DownloadRecord.self, from: data)
            else {
                let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []

                if files.contains(where: { $0.hasPrefix("media.") }) {
                    // Never delete media just because its record can't be read
                    logger.error("Unable to read download record in \(folder.lastPathComponent)")
                } else {
                    // Leftovers from a download that never got a record
                    try? FileManager.default.removeItem(at: folder)
                }
                continue
            }

            loaded[record.id] = record
        }

        records = loaded
    }

    /// Updates a record in memory and on disk.
    private func update(_ record: DownloadRecord, persist: Bool = true) {
        records[record.id] = record

        guard persist else { return }

        do {
            let data = try JSONEncoder().encode(record)
            try data.write(to: directory(for: record.id).appending(path: Self.recordFileName), options: .atomic)
        } catch {
            logger.error("Unable to save download record: \(error.localizedDescription)")
        }
    }

    // MARK: - Tasks

    /// Matches running background tasks to records after a relaunch, and fails
    /// records whose task no longer exists.
    private func reconnectTasks() {
        session.getAllTasks { [weak self] tasks in
            Task { @MainActor in
                guard let self else { return }

                let runningIDs = Set(tasks.compactMap(\.taskDescription))

                for task in tasks {
                    guard let itemID = task.taskDescription, self.tasks[itemID] == nil else { continue }

                    self.tasks[itemID] = task
                }

                for record in self.records.values where record.status == .queued || record.status == .downloading {
                    // Only downloads from a previous launch can have lost their task
                    guard record.dateAdded < self.launchDate, !runningIDs.contains(record.id) else { continue }

                    // Queued downloads that never started just wait their turn
                    if record.status == .queued, record.downloadURL != nil {
                        continue
                    }

                    var record = record
                    record.status = .failed
                    record.errorMessage = L10n.Downloads.interrupted
                    self.update(record)
                }

                self.hasReconnectedTasks = true
                self.startQueuedDownloads()
            }
        }
    }

    /// Starts queued downloads in the order they were added, up to `limit` running at once.
    ///
    /// - Parameter limit: The maximum number of running downloads, or `nil` to start all of them.
    private func startQueuedDownloads(limit: Int? = DownloadManager.maximumActiveDownloads) {
        // Until then, running tasks of a previous launch aren't known
        guard hasReconnectedTasks else { return }

        let waiting = records.values
            .filter { $0.status == .queued && tasks[$0.id] == nil }
            .sorted { $0.dateAdded < $1.dateAdded }

        let available = limit.map { max(0, $0 - tasks.count) } ?? waiting.count

        for record in waiting.prefix(available) {
            start(record)
        }
    }

    private func start(_ record: DownloadRecord) {
        let resumeDataURL = directory(for: record.id).appending(path: Self.resumeDataFileName)

        let task: URLSessionDownloadTask

        if !record.quality.isTranscoded, let resumeData = try? Data(contentsOf: resumeDataURL) {
            try? FileManager.default.removeItem(at: resumeDataURL)
            task = session.downloadTask(withResumeData: resumeData)
        } else if let downloadURL = record.downloadURL {
            var request = URLRequest(url: downloadURL)
            request.timeoutInterval = 120
            task = session.downloadTask(with: request)
        } else {
            fail(record.id, message: L10n.Downloads.interrupted)
            return
        }

        task.taskDescription = record.id
        tasks[record.id] = task
        task.resume()

        logger.info("Started download", metadata: ["itemID": .string(record.id), "quality": .string(record.quality.rawValue)])
    }

    /// Cancels tasks of a previous launch that haven't been matched to a record yet.
    private func cancelUntrackedTasks(for itemID: String) {
        session.getAllTasks { [weak self] tasks in
            Task { @MainActor in
                for task in tasks where task.taskDescription == itemID && self?.tasks[itemID] !== task {
                    task.cancel()
                }
            }
        }
    }

    /// Whether a callback comes from the current task of a download, and not one that was replaced.
    private func isCurrent(_ task: URLSessionTask, for itemID: String) -> Bool {
        guard let current = tasks[itemID] else { return true }

        return current === task
    }

    private func fail(_ itemID: String, message: String) {
        guard var record = records[itemID] else { return }

        record.status = .failed
        record.errorMessage = message
        update(record)

        logger.error("Download failed", metadata: ["itemID": .string(itemID), "error": .string(message)])
    }

    private func didFinishDownloading(task: URLSessionDownloadTask, to location: URL) {
        guard let itemID = task.taskDescription, isCurrent(task, for: itemID), var record = records[itemID] else {
            return
        }

        if let response = task.response as? HTTPURLResponse, !(200 ..< 300).contains(response.statusCode) {
            fail(itemID, message: L10n.Downloads.serverError(response.statusCode))
            return
        }

        let fileName = record.mediaFileName ?? "media.mkv"
        let destination = directory(for: itemID).appending(path: fileName)

        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)

            let size = (try? FileManager.default.attributesOfItem(atPath: destination.path(percentEncoded: false))[.size] as? Int64) ?? 0

            record.mediaFileName = fileName
            record.status = .completed
            record.errorMessage = nil
            record.bytesWritten = size
            record.bytesExpected = size
            update(record)

            logger.info("Finished download", metadata: ["itemID": .string(itemID)])
        } catch {
            fail(itemID, message: error.localizedDescription)
        }
    }

    private func didWriteData(task: URLSessionDownloadTask, totalBytesWritten: Int64, totalBytesExpected: Int64) {
        guard let itemID = task.taskDescription, isCurrent(task, for: itemID), var record = records[itemID] else { return }

        let isFirstUpdate = record.status != .downloading

        let now = Date.now

        // Throttle UI updates
        if !isFirstUpdate, let last = lastProgressUpdate[itemID], now.timeIntervalSince(last.date) < 0.5 {
            return
        }

        if let last = lastProgressUpdate[itemID] {
            let elapsed = now.timeIntervalSince(last.date)
            let rate = Double(totalBytesWritten - last.bytes) / max(elapsed, 0.001)

            // Smooth out bursts so the time left doesn't jump around
            speeds[itemID] = speeds[itemID].map { $0 * 0.8 + rate * 0.2 } ?? rate
        }

        lastProgressUpdate[itemID] = (now, totalBytesWritten)

        record.status = .downloading
        record.bytesWritten = totalBytesWritten

        if totalBytesExpected > 0 {
            record.bytesExpected = totalBytesExpected
        } else if let expected = record.bytesExpected, totalBytesWritten > expected {
            // Transcoded downloads have no known size, keep the estimate ahead of what's written
            record.bytesExpected = Int64(Double(totalBytesWritten) * 1.1)
        }

        update(record, persist: isFirstUpdate)
    }

    private func didComplete(task: URLSessionTask, error: Error?) {
        guard let itemID = task.taskDescription, isCurrent(task, for: itemID) else { return }

        tasks[itemID] = nil
        lastProgressUpdate[itemID] = nil
        speeds[itemID] = nil

        defer { startQueuedDownloads() }

        guard let error else { return }

        let nsError = error as NSError

        // Cancelled through `delete`
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled, records[itemID] == nil {
            return
        }

        if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            try? resumeData.write(to: directory(for: itemID).appending(path: Self.resumeDataFileName))
        }

        fail(itemID, message: error.localizedDescription)
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {

    // The session's delegate queue is the main queue

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The file at `location` is deleted when this returns, so handle it synchronously
        MainActor.assumeIsolated {
            didFinishDownloading(task: downloadTask, to: location)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        MainActor.assumeIsolated {
            didWriteData(
                task: downloadTask,
                totalBytesWritten: totalBytesWritten,
                totalBytesExpected: totalBytesExpectedToWrite
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        MainActor.assumeIsolated {
            didComplete(task: task, error: error)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        MainActor.assumeIsolated {
            backgroundCompletionHandler?()
            backgroundCompletionHandler = nil
        }
    }
}
