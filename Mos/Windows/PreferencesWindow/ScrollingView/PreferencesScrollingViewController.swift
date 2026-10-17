//
//  PreferencesScrollingViewController.swift
//  Mos
//  滚动选项界面
//  Created by Caldis on 2017/1/26.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesScrollingViewController: NSViewController, ScrollOptionsContextProviding {

    // Target application / device
    // - Using when the VC is inside the Application / Device Setting Popup
    var currentTargetApplication: Application? {
        didSet { targetDidChange() }
    }
    var currentTargetDevice: ScrollDevice? {
        didSet { targetDidChange() }
    }
    // 设定变更回调 (供外层容器同步继承状态)
    var onOptionsChanged: (() -> Void)?
    // UI Elements: 行标题
    @IBOutlet weak var smoothLabel: NSTextField?
    @IBOutlet weak var reverseLabel: NSTextField?
    @IBOutlet weak var dashLabel: NSTextField?
    @IBOutlet weak var toggleLabel: NSTextField?
    @IBOutlet weak var blockLabel: NSTextField?
    @IBOutlet weak var stepLabel: NSTextField?
    @IBOutlet weak var speedLabel: NSTextField?
    @IBOutlet weak var durationLabel: NSTextField?
    // UI Elements
    @IBOutlet weak var scrollSmoothCheckBox: NSButton!
    @IBOutlet weak var scrollReverseCheckBox: NSButton!
    @IBOutlet weak var dashKeyBindButton: NSButton!
    @IBOutlet weak var dashKeyDelButton: NSButton!
    @IBOutlet weak var toggleKeyBindButton: NSButton!
    @IBOutlet weak var toggleKeyDelButton: NSButton!
    @IBOutlet weak var disableKeyBindButton: NSButton!
    @IBOutlet weak var disableKeyDelButton: NSButton!
    @IBOutlet weak var scrollStepSlider: NSSlider!
    @IBOutlet weak var scrollStepInput: NSTextField!
    @IBOutlet weak var scrollStepStepper: NSStepper!
    @IBOutlet weak var scrollSpeedSlider: NSSlider!
    @IBOutlet weak var scrollSpeedInput: NSTextField!
    @IBOutlet weak var scrollSpeedStepper: NSStepper!
    @IBOutlet weak var scrollDurationSlider: NSSlider!
    @IBOutlet weak var scrollDurationInput: NSTextField!
    @IBOutlet weak var scrollDurationStepper: NSStepper!
    @IBOutlet weak var scrollDurationDescriptionLabel: NSTextField?
    @IBOutlet weak var resetToDefaultsButton: NSButton!
    var resetButtonHeightConstraint: NSLayoutConstraint?
    // Constants
    let DefaultConfigForCompare = OPTIONS_SCROLL_DEFAULT()
    private var scrollDurationDescriptionDefaultText: String?
    private let scrollDurationLockedDescription = NSLocalizedString(
        "scrollDurationLockedMessage",
        comment: "Message shown when simulate trackpad locks the duration setting"
    )
    // KeyRecorder for custom hotkey recording
    private let keyRecorder = KeyRecorder()
    private weak var currentRecordingPopup: NSButton?
    // 覆盖层上下文: 每行的 "恢复为全局设定" 按钮
    private var inheritButtons: [ScrollSetting: NSButton] = [:]
    private var inheritButtonOffsets: [ScrollSetting: NSLayoutConstraint] = [:]

    override func viewDidLoad() {
        // 禁止自动 Focus
        scrollStepInput.refusesFirstResponder = true
        scrollSpeedInput.refusesFirstResponder = true
        scrollDurationInput.refusesFirstResponder = true
        // 创建高度约束
        resetButtonHeightConstraint = resetToDefaultsButton.heightAnchor.constraint(equalToConstant: 24)
        resetButtonHeightConstraint?.isActive = true
        scrollDurationDescriptionDefaultText = scrollDurationDescriptionLabel?.stringValue
        // 设置 KeyRecorder 代理
        keyRecorder.delegate = self
        // 覆盖层上下文: 按设定项继承, 重置为全局设定
        setupProfileControls()
        // 读取设置
        syncViewWithOptions()
    }

    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        if let smoothPopover = segue.destinationController as? ScrollSmoothDetailSettingsPopoverViewController {
            smoothPopover.currentTargetApplication = currentTargetApplication
            smoothPopover.currentTargetDevice = currentTargetDevice
            smoothPopover.onOptionsChanged = { [weak self] in
                self?.syncViewWithOptions()
            }
        } else if let reversePopover = segue.destinationController as? ScrollReverseDetailSettingsPopoverViewController {
            reversePopover.currentTargetApplication = currentTargetApplication
            reversePopover.currentTargetDevice = currentTargetDevice
            reversePopover.onOptionsChanged = { [weak self] in
                self?.syncViewWithOptions()
            }
        }
    }
    
    // 平滑
    @IBAction func scrollSmoothClick(_ sender: NSButton) {
        updateScrollOptions([.smooth]) { $0.smooth = sender.state.rawValue != 0 }
        syncViewWithOptions()
    }

    // 翻转
    @IBAction func scrollReverseClick(_ sender: NSButton) {
        updateScrollOptions([.reverse]) { $0.reverse = sender.state.rawValue != 0 }
        syncViewWithOptions()
    }
    
    // 加速键 - 点击触发录制
    @IBAction func dashKeyButtonClick(_ sender: NSButton) {
        currentRecordingPopup = sender
        keyRecorder.startRecording(from: sender, mode: .singleKey)
    }
    // 加速键 - 清除绑定
    @IBAction func dashKeyDelButtonClick(_ sender: NSButton) {
        updateScrollOptions([.dash]) { $0.dash = nil }
        syncViewWithOptions()
    }
    // 转换键 - 点击触发录制
    @IBAction func toggleKeyButtonClick(_ sender: NSButton) {
        currentRecordingPopup = sender
        keyRecorder.startRecording(from: sender, mode: .singleKey)
    }
    // 转换键 - 清除绑定
    @IBAction func toggleKeyDelButtonClick(_ sender: NSButton) {
        updateScrollOptions([.toggle]) { $0.toggle = nil }
        syncViewWithOptions()
    }
    // 禁用键 - 点击触发录制
    @IBAction func disableKeyButtonClick(_ sender: NSButton) {
        currentRecordingPopup = sender
        keyRecorder.startRecording(from: sender, mode: .singleKey)
    }
    // 禁用键 - 清除绑定
    @IBAction func disableKeyDelButtonClick(_ sender: NSButton) {
        updateScrollOptions([.block]) { $0.block = nil }
        syncViewWithOptions()
    }
    
    // 步长
    @IBAction func scrollStepSliderChange(_ sender: NSSlider) {
        setScrollStep(value: sender.doubleValue)
    }
    @IBAction func scrollStepInputChange(_ sender: NSTextField) {
        setScrollStep(value: sender.doubleValue)
    }
    @IBAction func scrollStepStepperChange(_ sender: NSStepper) {
        setScrollStep(value: sender.doubleValue)
    }
    func setScrollStep(value: Double) {
        updateScrollOptions([.step]) { $0.step = value }
        syncViewWithOptions()
    }
    
    // 速度
    @IBAction func scrollSpeedSliderChange(_ sender: NSSlider) {
        setScrollSpeed(value: sender.doubleValue)
    }
    @IBAction func scrollSpeedInputChange(_ sender: NSTextField) {
        setScrollSpeed(value: sender.doubleValue)
    }
    @IBAction func scrollSpeedStepperChange(_ sender: NSStepper) {
        setScrollSpeed(value: sender.doubleValue)
    }
    func setScrollSpeed(value: Double) {
        updateScrollOptions([.speed]) { $0.speed = value }
        syncViewWithOptions()
    }
    
    // 过渡
    @IBAction func scrollDurationSliderChange(_ sender: NSSlider) {
        setScrollDuration(value: sender.doubleValue)
    }
    @IBAction func scrollDurationInputChange(_ sender: NSTextField) {
        setScrollDuration(value: sender.doubleValue)
    }
    @IBAction func scrollDurationStepperChange(_ sender: NSStepper) {
        setScrollDuration(value: sender.doubleValue)
    }
    func setScrollDuration(value: Double) {
        let isLocked = getTargetApplicationScrollOptions().smoothSimTrackpad
        updateScrollOptions([.duration]) { scrollOptions in
            scrollOptions.duration = isLocked ? ScrollDurationLimits.simulateTrackpadDefault : value
        }
        syncViewWithOptions()
    }
    
    // 重置
    @IBAction func resetToDefaultClick(_ sender: NSButton) {
        // 覆盖层上下文: 恢复为全局设定 (取消全部覆盖, 包括与全局恰好一致的)
        if let profile = currentScrollProfile {
            profile.inherit(profile.supportedSettings)
        } else {
            Options.shared.scroll = OPTIONS_SCROLL_DEFAULT()
        }
        syncViewWithOptions()
    }

}

/**
 * 工具函数
 **/
extension PreferencesScrollingViewController {
    // 同步界面与设置
    func syncViewWithOptions() {
        // 滚动配置 (覆盖层上下文中为合并后的生效值)
        let scroll = getTargetApplicationScrollOptions()
        // 平滑
        scrollSmoothCheckBox.state = NSControl.StateValue(rawValue: scroll.smooth ? 1 : 0)
        scrollSmoothCheckBox.isEnabled = isSettingEditable(.smooth)
        // 翻转
        scrollReverseCheckBox.state = NSControl.StateValue(rawValue: scroll.reverse ? 1 : 0)
        scrollReverseCheckBox.isEnabled = isSettingEditable(.reverse)
        // 加速键
        updateHotkeyButton(dashKeyBindButton, delButton: dashKeyDelButton, hotkey: scroll.dash, enabled: isSettingEditable(.dash))
        // 转换键
        updateHotkeyButton(toggleKeyBindButton, delButton: toggleKeyDelButton, hotkey: scroll.toggle, enabled: isSettingEditable(.toggle))
        // 禁用键
        updateHotkeyButton(disableKeyBindButton, delButton: disableKeyDelButton, hotkey: scroll.block, enabled: isSettingEditable(.block))
        // 步长
        let step = scroll.step
        let isStepEditable = isSettingEditable(.step)
        scrollStepSlider.doubleValue = step
        scrollStepSlider.isEnabled = isStepEditable
        scrollStepStepper.doubleValue = step
        scrollStepStepper.isEnabled = isStepEditable
        scrollStepInput.stringValue = String(format: "%.2f", step)
        scrollStepInput.isEnabled = isStepEditable
        // 速度
        let speed = scroll.speed
        let isSpeedEditable = isSettingEditable(.speed)
        scrollSpeedSlider.doubleValue = speed
        scrollSpeedSlider.isEnabled = isSpeedEditable
        scrollSpeedStepper.doubleValue = speed
        scrollSpeedStepper.isEnabled = isSpeedEditable
        scrollSpeedInput.stringValue = String(format: "%.2f", speed)
        scrollSpeedInput.isEnabled = isSpeedEditable
        // 过渡
        let isSimTrackpadEnabled = scroll.smoothSimTrackpad
        let isDurationEditable = isSettingEditable(.duration) && !isSimTrackpadEnabled
        let resolvedDuration: Double
        if isSimTrackpadEnabled {
            resolvedDuration = ScrollDurationLimits.simulateTrackpadDefault
            // 覆盖层的时长由解析层统一约束, 只需修正全局配置
            if currentScrollProfile == nil && scroll.duration != resolvedDuration {
                scroll.duration = resolvedDuration
            }
        } else {
            resolvedDuration = scroll.duration
        }
        scrollDurationSlider.doubleValue = resolvedDuration
        scrollDurationSlider.isEnabled = isDurationEditable
        scrollDurationStepper.doubleValue = resolvedDuration
        scrollDurationStepper.isEnabled = isDurationEditable
        scrollDurationInput.stringValue = String(format: "%.2f", resolvedDuration)
        scrollDurationInput.isEnabled = isDurationEditable
        if isSimTrackpadEnabled {
            scrollDurationDescriptionLabel?.stringValue = scrollDurationLockedDescription
        } else if let defaultText = scrollDurationDescriptionDefaultText {
            scrollDurationDescriptionLabel?.stringValue = defaultText
        }
        // 继承状态
        updateInheritIndicators()
        // 更新重置按钮状态
        updateResetButtonState()
        onOptionsChanged?()
    }
    // 更新重置按钮状态与显示
    func updateResetButtonState() {
        let shouldShowResetButton = currentScrollProfile == nil ? differsFromDefaults() : differsFromGlobal()
        // 动画过渡
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = ANIMATION.duration
            context.allowsImplicitAnimation = true
            resetToDefaultsButton.animator().isEnabled = shouldShowResetButton
            resetToDefaultsButton.animator().alphaValue = shouldShowResetButton ? 1.0 : 0.0
            resetButtonHeightConstraint?.animator().constant = shouldShowResetButton ? 24 : 0
        }, completionHandler: {
            // 触发父视图窗口尺寸更新
            self.view.needsLayout = true
            self.view.layout()
            (self.parent as? PreferencesTabViewController)?.updateWindowSize()
        })
    }

    /// 键盘按键的完整名称映射 (仅用于 ScrollingView 按钮显示)
    private static let keyFullNames: [UInt16: String] = [
        // 修饰键
        KeyCode.commandL: "⌘ Command",
        KeyCode.commandR: "⌘ Command",
        KeyCode.optionL: "⌥ Option",
        KeyCode.optionR: "⌥ Option",
        KeyCode.shiftL: "⇧ Shift",
        KeyCode.shiftR: "⇧ Shift",
        KeyCode.controlL: "⌃ Control",
        KeyCode.controlR: "⌃ Control",
        KeyCode.fnL: "Fn",
        KeyCode.fnR: "Fn",
        // 特殊键
        49: "⎵ Space",
        51: "⌫ Delete",
        53: "⎋ Escape",
        36: "↩ Return",
        76: "↩ Return",
        48: "↹ Tab",
    ]

    /// 获取 ScrollHotkey 的完整显示名称
    /// 获取按键基础名称 (不含品牌前缀)
    private func getBaseDisplayName(for hotkey: ScrollHotkey) -> String {
        switch hotkey.type {
        case .keyboard:
            if let fullName = PreferencesScrollingViewController.keyFullNames[hotkey.code] {
                return fullName
            }
            return KeyCode.keyMap[hotkey.code] ?? "Key \(hotkey.code)"
        case .mouse:
            if LogiCenter.shared.isLogiCode(hotkey.code) {
                return (LogiCenter.shared.name(forMosCode: hotkey.code) ?? "")
            }
            return KeyCode.mouseMap[hotkey.code] ?? "🖱\(hotkey.code)"
        }
    }

    /// 获取完整显示名称 (含品牌前缀, 用于纯文本场景)
    private func getFullDisplayName(for hotkey: ScrollHotkey) -> String {
        let baseName = getBaseDisplayName(for: hotkey)
        if let brand = BrandTag.brandForCode(hotkey.code) {
            return BrandTag.prefixedName(baseName, brand: brand)
        }
        return baseName
    }

    /// 更新热键按钮的显示文本和删除按钮可见性
    private func updateHotkeyButton(_ button: NSButton?, delButton: NSButton?, hotkey: ScrollHotkey?, enabled: Bool) {
        guard let button = button else { return }

        let hasBound = hotkey != nil

        // 设置按钮标题
        if let hotkey = hotkey {
            let baseName = getBaseDisplayName(for: hotkey)
            if let brand = BrandTag.brandForCode(hotkey.code) {
                // 品牌按键: image=tag, title=名称, 左图右文
                button.image = BrandTag.createTagImage(brand: brand, fontSize: 7, height: 14, padH: 5, marginRight: 4)
                button.imagePosition = .imageLeft
                button.title = baseName
            } else {
                button.image = nil
                button.imagePosition = .noImage
                button.title = getFullDisplayName(for: hotkey)
            }
        } else {
            button.image = nil
            button.imagePosition = .noImage
            button.title = NSLocalizedString("Disabled", comment: "Hotkey disabled state")
        }

        button.isEnabled = enabled

        // 设置删除按钮可见性：仅在有绑定且启用时显示
        delButton?.alphaValue = (hasBound && enabled) ? 1.0 : 0.0
        delButton?.isEnabled = hasBound && enabled
    }
}

// MARK: - KeyRecorderDelegate
extension PreferencesScrollingViewController: KeyRecorderDelegate {
    func onEventRecorded(_ recorder: KeyRecorder, didRecordEvent event: InputEvent, isDuplicate: Bool) {
        guard let popup = currentRecordingPopup else { return }

        let hotkey = ScrollHotkey(from: event)

        if popup === dashKeyBindButton {
            updateScrollOptions([.dash]) { $0.dash = hotkey }
        } else if popup === toggleKeyBindButton {
            updateScrollOptions([.toggle]) { $0.toggle = hotkey }
        } else if popup === disableKeyBindButton {
            updateScrollOptions([.block]) { $0.block = hotkey }
        }

        currentRecordingPopup = nil
        syncViewWithOptions()
    }
}

// MARK: - 按设定项继承
extension PreferencesScrollingViewController {

    private var settingLabels: [(ScrollSetting, NSTextField?)] {
        return [
            (.smooth, smoothLabel),
            (.reverse, reverseLabel),
            (.dash, dashLabel),
            (.toggle, toggleLabel),
            (.block, blockLabel),
            (.step, stepLabel),
            (.speed, speedLabel),
            (.duration, durationLabel),
        ]
    }

    /// 目标可能在视图加载后才设置 (容器的 embed segue), 此时补做覆盖层初始化
    private func targetDidChange() {
        guard isViewLoaded else { return }
        setupProfileControls()
        syncViewWithOptions()
    }

    private func setupProfileControls() {
        guard currentScrollProfile != nil else { return }
        resetToDefaultsButton.title = NSLocalizedString("resetToGlobalSettings", comment: "Button that removes every override of an app or device so it follows the global settings")
        setupInheritButtons()
    }

    /// 覆盖层上下文中, 在每行标题文字左侧放置 "恢复为全局设定" 按钮 (仅已覆盖时可见)
    private func setupInheritButtons() {
        guard inheritButtons.isEmpty else { return }
        for (setting, label) in settingLabels {
            guard let label = label, let index = ScrollSetting.allCases.firstIndex(of: setting) else { continue }
            let button = NSButton(title: "", target: self, action: #selector(inheritSettingClick(_:)))
            button.tag = index
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.image = PreferencesScrollingViewController.inheritButtonImage()
            button.toolTip = NSLocalizedString("scrollSettingUseGlobalTooltip", comment: "Tooltip of the button that makes an overridden scroll setting follow the global settings again")
            if #available(macOS 10.14, *) {
                button.contentTintColor = NSColor.controlAccentColor
            }
            button.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(button)
            let offset = button.trailingAnchor.constraint(equalTo: label.trailingAnchor)
            NSLayoutConstraint.activate([
                offset,
                button.centerYAnchor.constraint(equalTo: label.centerYAnchor),
                button.widthAnchor.constraint(equalToConstant: 12),
                button.heightAnchor.constraint(equalToConstant: 12),
            ])
            inheritButtons[setting] = button
            inheritButtonOffsets[setting] = offset
        }
    }

    private static func inheritButtonImage() -> NSImage? {
        if #available(macOS 11.0, *) {
            let image = NSImage(systemSymbolName: "arrow.uturn.backward.circle.fill", accessibilityDescription: nil)
            return image?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .regular))
        }
        let image = NSImage(named: NSImage.refreshTemplateName)
        image?.size = NSSize(width: 10, height: 10)
        return image
    }

    @objc private func inheritSettingClick(_ sender: NSButton) {
        guard ScrollSetting.allCases.indices.contains(sender.tag) else { return }
        currentScrollProfile?.inherit([ScrollSetting.allCases[sender.tag]])
        syncViewWithOptions()
    }

    /// 与全局不同的行: 标题使用主文字色, 并显示恢复按钮
    private func updateInheritIndicators() {
        guard let profile = currentScrollProfile else { return }
        let differing = profile.differingSettings()
        for (setting, label) in settingLabels {
            guard let label = label else { continue }
            let isOverridden = differing.contains(setting)
            label.textColor = isOverridden ? NSColor.labelColor : NSColor.secondaryLabelColor
            if !isSettingEditable(setting) {
                label.toolTip = NSLocalizedString("scrollSettingNotPerDeviceTooltip", comment: "Tooltip on scroll settings that cannot be overridden per device")
            } else {
                label.toolTip = isOverridden ? nil : NSLocalizedString("scrollSettingInheritedTooltip", comment: "Tooltip on scroll settings that currently follow the global settings")
            }
            guard let button = inheritButtons[setting] else { continue }
            button.isHidden = !isOverridden
            // 标题右对齐, 按钮紧贴文字左侧
            let textWidth = ceil(label.attributedStringValue.size().width)
            inheritButtonOffsets[setting]?.constant = -(textWidth + 6)
        }
    }

    /// 全局配置是否与默认配置不同
    private func differsFromDefaults() -> Bool {
        return Options.shared.scroll.values != DefaultConfigForCompare.values
    }

    /// 覆盖层是否有与全局不同的设定项
    private func differsFromGlobal() -> Bool {
        return !(currentScrollProfile?.differingSettings().isEmpty ?? true)
    }
}
