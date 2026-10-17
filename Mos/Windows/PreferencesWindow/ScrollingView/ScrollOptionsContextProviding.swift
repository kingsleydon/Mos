//
//  ScrollOptionsContextProviding.swift
//  Mos
//  Shared helpers for view controllers that operate on scroll options.
//  Created by Caldis on 10/25/2025.
//  Copyright © 2025 Caldis. All rights reserved.
//

import Cocoa

protocol ScrollOptionsContextProviding: AnyObject {
    var currentTargetApplication: Application? { get set }
    var currentTargetDevice: ScrollDevice? { get set }
}

extension ScrollOptionsContextProviding {
    /// 当前编辑的覆盖层; nil 表示编辑全局配置
    var currentScrollProfile: ScrollProfile? {
        if let device = currentTargetDevice { return device }
        return currentTargetApplication
    }

    /// 用于界面展示的生效配置. 覆盖层上下文中为只读快照, 修改须经 updateScrollOptions
    func getTargetApplicationScrollOptions() -> OPTIONS_SCROLL_DEFAULT {
        guard let profile = currentScrollProfile else { return Options.shared.scroll }
        return OPTIONS_SCROLL_DEFAULT(values: profile.effectiveValues())
    }

    /// 修改设定项: 覆盖层上下文中先转为覆盖, 再写入覆盖层自身的配置; 改回与全局一致时恢复继承
    func updateScrollOptions(_ settings: Set<ScrollSetting>, _ body: (OPTIONS_SCROLL_DEFAULT) -> Void) {
        guard let profile = currentScrollProfile else {
            body(Options.shared.scroll)
            return
        }
        guard settings.isSubset(of: profile.supportedSettings) else { return }
        profile.beginOverriding(settings)
        body(profile.scroll)
        profile.inheritSettingsMatchingGlobal(settings)
    }

    func isSettingEditable(_ setting: ScrollSetting) -> Bool {
        guard let profile = currentScrollProfile else { return true }
        return profile.supportedSettings.contains(setting)
    }

    func updateSmoothDependentControl(_ control: NSButton?, isOn: Bool) {
        // Keep the original sync logic shared between the preferences panel and the popover.
        let scroll = getTargetApplicationScrollOptions()
        control?.state = NSControl.StateValue(rawValue: isOn ? 1 : 0)
        control?.isEnabled = isSettingEditable(.smooth) && scroll.smooth
    }

    func updateSimulateTrackpadControl(_ control: NSButton?) {
        let scroll = getTargetApplicationScrollOptions()
        updateSmoothDependentControl(control, isOn: scroll.smoothSimTrackpad)
    }

    func updateReverseDependentControl(_ control: NSButton?, isOn: Bool) {
        let scroll = getTargetApplicationScrollOptions()
        control?.state = NSControl.StateValue(rawValue: isOn ? 1 : 0)
        control?.isEnabled = isSettingEditable(.reverse) && scroll.reverse
    }
}
