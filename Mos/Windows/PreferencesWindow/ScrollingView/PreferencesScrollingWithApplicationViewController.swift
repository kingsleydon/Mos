//
//  PreferencesScrollingWithApplicationViewController.swift
//  Mos
//  滚动窗口容器 (例外应用 / 例外设备)
//  Created by Caldis on 31/10/2019.
//  Copyright © 2019 Caldis. All rights reserved.
//

import Cocoa

class PreferencesScrollingWithApplicationViewController: NSViewController {

    // Parent view
    private var parentTableView: NSTableView?
    private var parentTableRow: Int!
    // Target application / device
    private var currentTargetApplication: Application?
    private var currentTargetDevice: ScrollDevice?
    private var currentContentViewController: PreferencesScrollingViewController?
    // UI Elements
    @IBOutlet weak var currentTargetApplicationIcon: NSImageView!
    @IBOutlet weak var currentTargetApplicationName: NSTextField!
    @IBOutlet weak var inheritGlobalSettingCheckBox: NSButton!

    private var currentScrollProfile: ScrollProfile? {
        if let device = currentTargetDevice { return device }
        return currentTargetApplication
    }

    override func viewDidLoad() {
        // 初始化显示内容
        if let device = currentTargetDevice {
            currentTargetApplicationIcon.image = PreferencesScrollingWithApplicationViewController.deviceIcon()
            currentTargetApplicationIcon.toolTip = device.identity
            currentTargetApplicationName.stringValue = device.getName()
        } else {
            currentTargetApplicationIcon.image = currentTargetApplication?.getIcon()
            currentTargetApplicationIcon.toolTip = currentTargetApplication?.path
            currentTargetApplicationName.stringValue = currentTargetApplication?.getName() ?? ""
        }
        // 部分设定项被覆盖时显示为混合状态
        inheritGlobalSettingCheckBox.allowsMixedState = true
        // 读取设置
        syncViewWithOptions()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        // 没有任何覆盖与自定义名称的设备无需保留
        if let device = currentTargetDevice, device.overrides.isEmpty, (device.displayName ?? "").isEmpty {
            Options.shared.device.devices.remove(from: device.identity)
        }
    }

    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        currentContentViewController = (segue.destinationController as! PreferencesScrollingViewController)
        if let vaildContentViewController = currentContentViewController {
            vaildContentViewController.currentTargetApplication = currentTargetApplication
            vaildContentViewController.currentTargetDevice = currentTargetDevice
            vaildContentViewController.onOptionsChanged = { [weak self] in
                self?.syncViewWithOptions()
            }
        }
    }

    public func updateTargetApplication(with target: Application?) {
        currentTargetApplication = target
        if let vaildContentViewController = currentContentViewController, let validTargetApplication = currentTargetApplication {
            vaildContentViewController.currentTargetApplication = validTargetApplication
        }
    }
    public func updateTargetDevice(with target: ScrollDevice?) {
        currentTargetDevice = target
        if let vaildContentViewController = currentContentViewController, let validTargetDevice = currentTargetDevice {
            vaildContentViewController.currentTargetDevice = validTargetDevice
        }
    }
    public func updateParentData(with target: NSTableView, for row: Int) {
        parentTableView = target
        parentTableRow = row
    }

    // 名称
    @IBAction func currentTargetApplicationNameChange(_ sender: NSTextField) {
        let name = sender.stringValue
        if let device = currentTargetDevice {
            device.displayName = name
            return
        }
        if name.count > 0 {
            currentTargetApplication?.displayName = name
            if let validParentTableView = parentTableView, let validParentTableRow = parentTableRow {
                validParentTableView.reloadData(forRowIndexes: [validParentTableRow], columnIndexes: [0, 1, 2])
            }
        }
    }

    // 继承: 有任何覆盖时恢复全部继承, 否则以当前生效值覆盖全部设定项
    // Logi divert 用量同步由 LogiUsageBootstrap 的 Options 订阅自动完成 (overrides didSet → .application)
    @IBAction func inheritGlobalSettingClick(_ sender: NSButton) {
        guard let profile = currentScrollProfile else { return }
        if profile.overrides.isEmpty {
            profile.beginOverriding(profile.supportedSettings)
        } else {
            profile.inherit(profile.supportedSettings)
        }
        // 内容视图同步后会回调 syncViewWithOptions
        if let vaildContentViewController = currentContentViewController {
            vaildContentViewController.syncViewWithOptions()
        } else {
            syncViewWithOptions()
        }
    }
}

/**
 * 工具函数
 **/
extension PreferencesScrollingWithApplicationViewController {
    // 同步界面与设置
    func syncViewWithOptions() {
        // 继承: 全部继承 / 部分覆盖 / 全部覆盖
        guard let profile = currentScrollProfile else {
            inheritGlobalSettingCheckBox?.state = .off
            return
        }
        if profile.overrides.isEmpty {
            inheritGlobalSettingCheckBox?.state = .on
        } else if profile.supportedSettings.isSubset(of: profile.overrides) {
            inheritGlobalSettingCheckBox?.state = .off
        } else {
            inheritGlobalSettingCheckBox?.state = .mixed
        }
    }

    private static func deviceIcon() -> NSImage? {
        if #available(macOS 11.0, *) {
            return NSImage(systemSymbolName: "computermouse", accessibilityDescription: nil)
        }
        return NSImage(named: NSImage.computerName)
    }
}
