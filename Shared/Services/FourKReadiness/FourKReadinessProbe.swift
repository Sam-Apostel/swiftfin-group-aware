//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AVFoundation
import AVKit
import Defaults
import FactoryKit
import Foundation
import JellyfinAPI
import Network
import UIKit

/// The result of one check: the checklist and its one-line answer.
struct FourKReadinessReport: Equatable {

    var rows: [FourKReadinessRow]
    var scannedCount: Int
    var totalCount: Int

    var fixCount: Int {
        FourKReadiness.fixCount(rows)
    }
}

/// Gathers the facts for "What it takes to watch 4K on this TV": the TV, the network, the player and the library.
@MainActor
final class FourKReadinessProbe: ObservableObject {

    /// Bytes per bitrate test run: about 1.6 s at 100 Mbps.
    static let bitrateTestBytes = 20_000_000
    /// 4K videos looked at, at most.
    static let libraryScanLimit = 400

    @Published
    private(set) var report: FourKReadinessReport?
    @Published
    private(set) var isChecking = false

    private var checkTask: Task<Void, Never>?

    func check() {
        checkTask?.cancel()
        isChecking = true

        checkTask = Task { [weak self] in
            guard let self else { return }

            let report = await self.makeReport()

            guard !Task.isCancelled else { return }

            self.report = report
            self.isChecking = false
        }
    }

    // MARK: - Report

    private func makeReport() async -> FourKReadinessReport {
        let userSession = Container.shared.currentUserSession()
        let display = Self.displayFacts()
        let link = await Self.currentLink()

        var measuredMbps: Int?
        var serverFacts: ServerPlaybackFacts?
        var library: FourKLibraryFacts?
        var scannedCount = 0
        var totalCount = 0

        if let userSession {
            if link != .offline {
                measuredMbps = await Self.measureMbps(client: userSession.client)
            }

            serverFacts = await Container.shared.serverPlaybackFactsStore().facts(for: userSession)

            if let scan = await Self.scanLibrary(userSession: userSession, serverFacts: serverFacts) {
                library = scan.library
                scannedCount = scan.scanned
                totalCount = scan.total
            }
        }

        let player = FourKPlayerFacts(
            chosen: Defaults[.VideoPlayer.videoPlayerType],
            prefersNativeForHDR: Defaults[.VideoPlayer.nativePlayerForHDR],
            forcesHDRConversion: StoredValues[.User.forceHDRTranscode],
            forcesDolbyVisionConversion: StoredValues[.User.forceDVTranscode]
        )

        let rows = FourKReadiness.rows(
            display: display,
            network: FourKNetworkFacts(link: link, measuredMbps: measuredMbps),
            player: player,
            library: library
        )

        return FourKReadinessReport(rows: rows, scannedCount: scannedCount, totalCount: totalCount)
    }

    // MARK: - Display

    /// What the TV reports. `nil` off tvOS, where the screen is built in.
    static func displayFacts() -> FourKDisplayFacts? {
        #if os(tvOS)
        let window = UIApplication.shared.keyWindow
        let nativeSize = window?.screen.nativeBounds.size ?? .zero
        let modeSize = window?.screen.currentMode?.size ?? .zero
        let modes = AVPlayer.availableHDRModes

        return FourKDisplayFacts(
            width: Int(max(nativeSize.width, modeSize.width)),
            height: Int(max(nativeSize.height, modeSize.height)),
            isEligibleForHDR: AVPlayer.eligibleForHDRPlayback,
            supportsHDR10: modes.contains(.hdr10),
            supportsDolbyVision: modes.contains(.dolbyVision),
            matchesContent: window?.avDisplayManager.isDisplayCriteriaMatchingEnabled
        )
        #else
        return nil
        #endif
    }

    // MARK: - Network

    static func currentLink() async -> FourKNetworkFacts.Link {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let state = ResumeState()

            // Called on the monitor's serial queue, so `state` needs no lock.
            monitor.pathUpdateHandler = { path in
                guard !state.didResume else { return }

                state.didResume = true
                monitor.cancel()
                continuation.resume(returning: link(for: path))
            }

            monitor.start(queue: DispatchQueue(label: "Couchfin.FourKReadiness"))
        }
    }

    nonisolated static func link(for path: NWPath) -> FourKNetworkFacts.Link {
        guard path.status == .satisfied else { return .offline }

        if path.usesInterfaceType(.wiredEthernet) {
            return .wired
        }

        if path.usesInterfaceType(.wifi) {
            return .wifi
        }

        return .other
    }

    /// The best of two runs of the server's bitrate test, in Mbps.
    static func measureMbps(client: JellyfinClient) async -> Int? {
        var best: Double?

        for _ in 0 ..< 2 {
            let start = Date()

            let response = try? await client.send(Paths.getBitrateTestBytes(size: bitrateTestBytes))

            guard response != nil else { break }

            let seconds = Date().timeIntervalSince(start)

            if seconds > 0 {
                best = max(best ?? 0, Double(bitrateTestBytes * 8) / seconds / 1_000_000)
            }
        }

        return best.map { Int($0.rounded()) }
    }

    // MARK: - Library

    /// The user's 4K movies and episodes, summarized with the playback verdict for this device.
    static func scanLibrary(
        userSession: UserSession,
        serverFacts: ServerPlaybackFacts?
    ) async -> (library: FourKLibraryFacts, scanned: Int, total: Int)? {
        var parameters = Paths.GetItemsParameters()
        parameters.userID = userSession.user.id
        parameters.includeItemTypes = [.movie, .episode]
        parameters.isRecursive = true
        parameters.minWidth = 3800
        parameters.fields = [.mediaSources]
        parameters.enableUserData = false
        parameters.limit = libraryScanLimit
        parameters.sortBy = [.sortName]

        guard let response = try? await userSession.client.send(Paths.getItems(parameters: parameters)) else { return nil }

        let items = response.value.items ?? []
        let compatibilityMode = Defaults[.VideoPlayer.Playback.compatibilityMode]
        let maxBitrate = PlaybackHealthCheck.maxBitrate(for: Defaults[.VideoPlayer.Playback.appMaximumBitrate])

        var profiles: [VideoPlayerType: DeviceProfile] = [:]
        var library = FourKLibraryFacts.empty

        for item in items {
            guard let source = item.mediaSources?.first else { continue }

            let video = source.mediaStreams?.first { $0.type == .video }

            guard TranscodeStreamClass.isFourK(width: video?.width ?? item.width, height: video?.height ?? item.height) else { continue }

            let player = VideoPlayerType.forPlayback(of: item)
            let profile = profiles[player] ?? DeviceProfile.build(for: player, compatibilityMode: compatibilityMode, maxBitrate: maxBitrate)
            profiles[player] = profile

            let verdict = PlaybackHealthClassifier.verdict(
                for: PlaybackHealthInput(
                    mediaSource: source,
                    isServerDecision: false,
                    deviceProfile: profile,
                    device: .current,
                    maxBitrate: maxBitrate,
                    server: serverFacts
                )
            )

            library = FourKReadiness.adding(source, verdict: verdict, to: library)
        }

        return (library, items.count, response.value.totalRecordCount ?? items.count)
    }
}

/// Whether a continuation was resumed.
private final class ResumeState {

    var didResume = false
}
