//
//  Application.swift
//  Mos
//  应用程序对象
//  Created by Caldis on 2018/2/20.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class Application: Codable, Equatable, ScrollProfile {
    
    // 基础
    var path: String // executablePath or bundlePath
    // 配置: 名称
    var displayName: String? = "" {
        didSet { Options.shared.markChanged(.application) }
    }
    // 配置: 已覆盖的设定项 (未覆盖的沿用全局配置)
    var overrides: Set<ScrollSetting> = [] {
        didSet { Options.shared.markChanged(.application) }
    }
    // 配置: 继承 (兼容旧版整体继承开关: 全部继承 / 全部覆盖)
    var inherit: Bool {
        get { return overrides.isEmpty }
        set { overrides = newValue ? [] : supportedSettings }
    }
    var supportedSettings: Set<ScrollSetting> {
        return Set(ScrollSetting.allCases)
    }
    // 配置: 滚动
    var scroll = OPTIONS_SCROLL_DEFAULT() {
        didSet { Options.shared.markChanged(.application) }
    }
    // 配置: 按钮绑定 (可选表示继承全局配置)
    var buttons: OPTIONS_BUTTONS_DEFAULT? {
        didSet { Options.shared.markChanged(.application) }
    }
    // 初始化
    init(path: String) {
        self.path = path
    }
    
    // Codable
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 基础
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        // 名称
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        // 继承: 新版按设定项记录; 旧版只有整体开关
        if let rawOverrides = try container.decodeIfPresent([String].self, forKey: .overrides) {
            overrides = Set(rawOverrides.compactMap { ScrollSetting(rawValue: $0) })
        } else {
            let legacyInherit = try container.decodeIfPresent(Bool.self, forKey: .inherit) ?? true
            overrides = legacyInherit ? [] : Set(ScrollSetting.allCases)
        }
        // 滚动
        scroll = try container.decodeIfPresent(OPTIONS_SCROLL_DEFAULT.self, forKey: .scroll) ?? OPTIONS_SCROLL_DEFAULT()
        // 按钮绑定
        buttons = try container.decodeIfPresent(OPTIONS_BUTTONS_DEFAULT.self, forKey: .buttons)
    }
    
    private enum CodingKeys: String, CodingKey {
        case path, displayName, inherit, overrides, scroll, buttons
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        // 同时写入旧版字段, 便于回退版本时仍能读取
        try container.encode(inherit, forKey: .inherit)
        try container.encode(overrides.map { $0.rawValue }.sorted(), forKey: .overrides)
        try container.encode(scroll, forKey: .scroll)
        try container.encodeIfPresent(buttons, forKey: .buttons)
    }

    // Equatable
    static func == (a: Application, b: Application) -> Bool {
        return a.path == b.path
    }
}

/**
 * 工具函数
 */
extension Application {
    // 基本信息
    func getIcon() -> NSImage {
        return Utils.getApplicationIcon(fromPath: path)
    }
    func getName() -> String {
        if let name = displayName, name.count > 0 {
            return name
        }
        return Utils.getApplicationName(fromPath: path)
    }
    // 配置
    func getStep() -> Double {
        return resolvedScrollOptions().step
    }
    func getSpeed() -> Double {
        return resolvedScrollOptions().speed
    }
    func getDuration() -> Double {
        return resolvedScrollOptions().durationTransition
    }
    // 功能
    // 未覆盖的设定项沿用全局配置, 结果与全局路径一致;
    // 已覆盖的设定项完全使用应用自身配置, 不再受全局开关联动 (见 #1011)
    func isSmooth(_ block: Bool) -> Bool {
        if block { return false }
        return resolvedScrollOptions().smooth
    }
    func isReverse() -> Bool {
        return resolvedScrollOptions().reverse
    }
    func isReverseVertical() -> Bool {
        let target = resolvedScrollOptions()
        return target.reverse && target.reverseVertical
    }
    func isReverseHorizontal() -> Bool {
        let target = resolvedScrollOptions()
        return target.reverse && target.reverseHorizontal
    }
    func isSmoothVertical(_ block: Bool) -> Bool {
        if block { return false }
        let target = resolvedScrollOptions()
        return target.smooth && target.smoothVertical
    }
    func isSmoothHorizontal(_ block: Bool) -> Bool {
        if block { return false }
        let target = resolvedScrollOptions()
        return target.smooth && target.smoothHorizontal
    }
    // 按钮绑定
    func getButtonBindings() -> [ButtonBinding] {
        return buttons?.binding ?? Options.shared.buttons.binding
    }
}

private extension Application {
    func resolvedScrollOptions() -> ScrollValues {
        return effectiveValues()
    }
}
