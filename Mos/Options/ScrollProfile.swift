//
//  ScrollProfile.swift
//  Mos
//  按设定项继承的滚动配置层 (例外应用 / 例外设备)
//

import Cocoa

/// 滚动配置的值快照
struct ScrollValues: Equatable {
    var smooth: Bool
    var reverse: Bool
    var reverseVertical: Bool
    var reverseHorizontal: Bool
    var dash: ScrollHotkey?
    var toggle: ScrollHotkey?
    var block: ScrollHotkey?
    var step: Double
    var speed: Double
    var duration: Double
    var deadZone: Double
    var smoothSimTrackpad: Bool
    var smoothVertical: Bool
    var smoothHorizontal: Bool
    var durationBeforeSimTrackpadLock: Double?

    var durationTransition: Double {
        return OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: duration)
    }

    /// 界面可见的值: 数值按显示精度 (两位小数) 取整, 去掉不可见的时长记忆
    var visible: ScrollValues {
        var values = self
        values.step = ScrollValues.displayRounded(step)
        values.speed = ScrollValues.displayRounded(speed)
        values.duration = ScrollValues.displayRounded(duration)
        values.durationBeforeSimTrackpadLock = nil
        return values
    }

    private static func displayRounded(_ value: Double) -> Double {
        return (value * 100).rounded() / 100
    }
}

/// 可单独继承/覆盖的滚动设定项, 与偏好面板中的行一一对应
enum ScrollSetting: String, CaseIterable, Codable {
    case smooth, reverse, dash, toggle, block, step, speed, duration

    /// 设备只能覆盖与物理滚轮相关的设定; 热键不随设备区分
    static let deviceSupported: Set<ScrollSetting> = [.smooth, .reverse, .step, .speed, .duration]

    /// 把 source 中属于本设定项的字段合并到 target
    func merge(from source: ScrollValues, into target: inout ScrollValues) {
        switch self {
        case .smooth:
            target.smooth = source.smooth
            target.smoothVertical = source.smoothVertical
            target.smoothHorizontal = source.smoothHorizontal
            target.smoothSimTrackpad = source.smoothSimTrackpad
            target.durationBeforeSimTrackpadLock = source.durationBeforeSimTrackpadLock
        case .reverse:
            target.reverse = source.reverse
            target.reverseVertical = source.reverseVertical
            target.reverseHorizontal = source.reverseHorizontal
        case .dash:
            target.dash = source.dash
        case .toggle:
            target.toggle = source.toggle
        case .block:
            target.block = source.block
        case .step:
            target.step = source.step
        case .speed:
            target.speed = source.speed
        case .duration:
            target.duration = source.duration
        }
    }

    /// 把 source 中属于本设定项的字段写入 target 容器 (触发持久化)
    func copy(from source: ScrollValues, to target: OPTIONS_SCROLL_DEFAULT) {
        var values = target.values
        merge(from: source, into: &values)
        target.apply(values)
    }
}

/// 覆盖层: 未覆盖的设定项沿用全局配置
protocol ScrollProfile: AnyObject {
    var scroll: OPTIONS_SCROLL_DEFAULT { get set }
    var overrides: Set<ScrollSetting> { get set }
    var supportedSettings: Set<ScrollSetting> { get }
}

extension ScrollProfile {
    func isOverridden(_ setting: ScrollSetting) -> Bool {
        return overrides.contains(setting)
    }

    /// 本层与全局合并后的生效值 (仅本层, 不含其他覆盖层)
    func effectiveValues() -> ScrollValues {
        return ScrollOptionsResolver.resolve(global: Options.shared.scroll, layers: [self])
    }

    /// 开始覆盖指定设定项: 先把当前生效值物化到本层, 再标记为覆盖
    func beginOverriding(_ settings: Set<ScrollSetting>) {
        let pending = settings.intersection(supportedSettings).subtracting(overrides)
        guard !pending.isEmpty else { return }
        let effective = effectiveValues()
        for setting in pending {
            setting.copy(from: effective, to: scroll)
        }
        overrides.formUnion(pending)
    }

    /// 停止覆盖, 回到继承全局
    func inherit(_ settings: Set<ScrollSetting>) {
        overrides.subtract(settings)
    }
}

/// 解析顺序: 全局 → 例外应用 → 例外设备 (后者优先)
enum ScrollOptionsResolver {
    static func resolve(global: OPTIONS_SCROLL_DEFAULT, layers: [ScrollProfile?]) -> ScrollValues {
        var values = global.values
        for case let layer? in layers where !layer.overrides.isEmpty {
            let layerValues = layer.scroll.values
            for setting in layer.overrides {
                setting.merge(from: layerValues, into: &values)
            }
        }
        // 模拟触控板会锁定过渡时长; 平滑与过渡可能来自不同层, 在合并结果上统一约束
        if values.smoothSimTrackpad {
            values.duration = ScrollDurationLimits.simulateTrackpadDefault
        }
        return values
    }

    /// Mos 是否处理该事件: 应用与设备需各自通过 (未列出时取决于白名单模式, 列出时取决于是否停用)
    static func isActive(application: Application?, device: ScrollDevice?, applicationAllowlist: Bool, deviceAllowlist: Bool) -> Bool {
        let applicationActive = application.map { !$0.disabled } ?? !applicationAllowlist
        let deviceActive = device.map { !$0.disabled } ?? !deviceAllowlist
        return applicationActive && deviceActive
    }

    static func isActive(application: Application?, device: ScrollDevice?) -> Bool {
        return isActive(
            application: application,
            device: device,
            applicationAllowlist: Options.shared.application.allowlist,
            deviceAllowlist: Options.shared.device.allowlist
        )
    }

    static func resolve(application: Application?, device: ScrollDevice?) -> ScrollValues {
        return resolve(global: Options.shared.scroll, layers: [application, device])
    }
}

extension ScrollSetting {
    var localizedName: String {
        switch self {
        case .smooth: return NSLocalizedString("scrollSettingNameSmooth", comment: "Short name of the smooth scrolling setting")
        case .reverse: return NSLocalizedString("scrollSettingNameReverse", comment: "Short name of the reverse scrolling setting")
        case .dash: return NSLocalizedString("scrollSettingNameDash", comment: "Short name of the dash key setting")
        case .toggle: return NSLocalizedString("scrollSettingNameToggle", comment: "Short name of the toggle key setting")
        case .block: return NSLocalizedString("scrollSettingNameBlock", comment: "Short name of the block key setting")
        case .step: return NSLocalizedString("scrollSettingNameStep", comment: "Short name of the scroll step setting")
        case .speed: return NSLocalizedString("scrollSettingNameSpeed", comment: "Short name of the scroll speed setting")
        case .duration: return NSLocalizedString("scrollSettingNameDuration", comment: "Short name of the scroll duration setting")
        }
    }
}

extension ScrollProfile {
    /// 列表中展示的覆盖摘要
    func overrideSummary() -> String {
        if overrides.isEmpty {
            return NSLocalizedString("overridesSummaryNone", comment: "Summary for an override entry that inherits every setting")
        }
        if supportedSettings.isSubset(of: overrides) {
            return NSLocalizedString("overridesSummaryAll", comment: "Summary for an override entry that overrides every setting")
        }
        let separator = NSLocalizedString("overridesSummarySeparator", comment: "Separator between setting names in the override summary")
        return ScrollSetting.allCases.filter { overrides.contains($0) }.map { $0.localizedName }.joined(separator: separator)
    }
}
