//
//  UpdateManager.swift
//  Mos
//  Updates management via Sparkle
//

import Cocoa
import Sparkle

final class UpdateManager: NSObject {

    static let shared = UpdateManager()

    /// Fork 构建 (MOS_FORK_BUILD) 不使用上游的 Sparkle 更新源: 上游更新会覆盖 fork 版本
    #if MOS_FORK_BUILD
    static let isEnabled = false
    #else
    static let isEnabled = true
    #endif

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    private override init() {
        super.init()
        NSLog("Module initialized: UpdateManager")
    }
}

extension UpdateManager {

    func scheduleCheckOnAppStartIfNeeded() {
        guard UpdateManager.isEnabled, Options.shared.update.checkOnAppStart else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.checkForUpdatesInBackground()
        }
    }

    func checkForUpdates() {
        guard UpdateManager.isEnabled else { return }
        updaterController.checkForUpdates(nil)
    }

    func checkForUpdatesInBackground() {
        guard UpdateManager.isEnabled else { return }
        updaterController.updater.checkForUpdatesInBackground()
    }
}

extension UpdateManager: SPUUpdaterDelegate {

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        Options.shared.update.includingBetaVersion ? ["beta"] : []
    }
}

