//
//  PreferencesApplicationViewController.swift
//  Mos
//  覆盖设置界面 (例外应用 / 例外设备)
//  Created by Caldis on 2017/1/29.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesApplicationViewController: NSViewController {

    // 列表类型
    enum OverridesMode: Int {
        case applications = 0
        case devices = 1
    }
    private var mode = OverridesMode.applications

    // MARK: - UI Elements
    // 白名单
    @IBOutlet weak var allowlistModeCheckBox: NSButton!
    // 表格
    @IBOutlet weak var tableHead: NSVisualEffectView!
    @IBOutlet weak var tableHeadTitle: NSTextField?
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var tableFoot: NSView!
    @IBOutlet weak var tableEmpty: NSView!
    @IBOutlet weak var tableEmptyTitle: NSTextField?
    @IBOutlet weak var tableEmptyDescription: NSTextField?
    @IBOutlet weak var tableEmptyImage: NSImageView?
    // 按钮
    @IBOutlet weak var createButton: PrimaryButton!
    @IBOutlet weak var createButtonTitle: NSTextField?
    @IBOutlet weak var createButtonDescription: NSTextField?
    @IBOutlet weak var addButton: NSButton!
    @IBOutlet weak var delButton: NSButton!
    // 选项菜单
    @IBOutlet var applicationSourceMenuControl: NSMenu!
    @IBOutlet weak var runningAndInstalledManuItem: NSMenuItem!
    private var runningAndInstalledMenuChildrenContainer: NSMenu!
    @IBOutlet weak var manuallySelectFromFinderMenuItem: NSMenuItem!
    // 类型切换 (代码创建)
    private let modeControl = NSSegmentedControl()
    // 设备菜单
    private let deviceSourceMenu = NSMenu(title: "")
    private var deviceMenuInfos: [String: PointingDeviceInfo] = [:]
    // Storyboard 中已本地化的应用文案, 切回应用列表时还原
    private var applicationTexts: [NSTextField: String] = [:]
    private var applicationEmptyImage: NSImage?

    override func viewDidLoad() {
        // 为 "Running Applications" 菜单项动态创建 submenu (避免 Storyboard 中的 menu 父子关系警告)
        runningAndInstalledMenuChildrenContainer = NSMenu(title: "")
        runningAndInstalledManuItem.submenu = runningAndInstalledMenuChildrenContainer
        // 设置图标
        Utils.attachImage(to: runningAndInstalledManuItem, withImage: #imageLiteral(resourceName: "SF.wand.and.rays.inverse"))
        Utils.attachImage(to: manuallySelectFromFinderMenuItem, withImage: #imageLiteral(resourceName: "SF.tray"))
        // 设置表格代理
        tableView.delegate = self
        // 启用开关列, 类型切换
        setupEnabledColumn()
        setupModeControl()
        for field in [tableHeadTitle, tableEmptyTitle, tableEmptyDescription, createButtonTitle, createButtonDescription] {
            if let field = field { applicationTexts[field] = field.stringValue }
        }
        applicationEmptyImage = tableEmptyImage?.image
        // 读取设置
        syncViewWithOptions()
        // 初始化按钮状态
        updateDelButtonState()
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        alignTableHeadTitle()
    }
    override func viewWillAppear() {
        // 设备可能在面板外被识别, 每次显示时刷新
        tableView.reloadData()
        // 检查表格数据
        toggleNoDataHint()
        // 设置添加按钮回调
        setupAddButtonCallback()
    }

    // 主添加按钮
    private func setupAddButtonCallback() {
        createButton.onMouseDown = { [weak self] _ in
            guard let self = self else { return }
            guard let sender = self.createButton else { return }
            let position = NSPoint(x: sender.frame.origin.x - 40, y: sender.frame.origin.y - 44)
            self.openSourceMenu(sender, position)
            self.tableView.reloadData()
        }
    }

    // 白名单模式 (应用与设备各自独立)
    @IBAction func allowListModeClick(_ sender: NSButton) {
        let isOn = sender.state.rawValue != 0
        switch mode {
        case .applications: Options.shared.application.allowlist = isOn
        case .devices: Options.shared.device.allowlist = isOn
        }
        syncViewWithOptions()
    }

    // 列表底部按钮
    @IBAction func addItemClick(_ sender: NSButton) {
        // 添加
        let position = NSPoint(x: sender.frame.origin.x - 3, y: sender.frame.origin.y + 10)
        openSourceMenu(sender, position)
        // 重新加载
        tableView.reloadData()
    }
    @IBAction func addItemFromFinderClick(_ sender: NSMenuItem) {
        // 添加
        openFileSelectionPanel()
        // 重新加载
        tableView.reloadData()
    }
    @IBAction func removeItemClick(_ sender: NSButton) {
        // 确保选择了行
        guard tableView.selectedRow != -1 else { return }
        // 删除 (appScroll 用量清理由 LogiUsageBootstrap 的 Options 订阅自动完成)
        switch mode {
        case .applications:
            Options.shared.application.applications.remove(at: tableView.selectedRow)
        case .devices:
            Options.shared.device.devices.remove(at: tableView.selectedRow)
        }
        // 重新加载
        tableView.reloadData()
        // 立即更新空状态显示
        toggleNoDataHint()
        // 更新删除按钮状态
        updateDelButtonState()
    }

    // 白名单说明弹窗
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        guard mode == .devices,
              let hint = segue.destinationController as? NSViewController,
              let label = hint.view.subviews.compactMap({ $0 as? NSTextField }).first else {
            return
        }
        label.stringValue = NSLocalizedString("overridesDeviceAllowlistHint", comment: "Help popover text for the allow list mode of the device list")
    }

    private func openSourceMenu(_ targetView: NSView, _ targetPosition: NSPoint) {
        switch mode {
        case .applications:
            openRunningApplicationPanel(targetView, targetPosition)
        case .devices:
            openConnectedDevicePanel(targetView, targetPosition)
        }
    }
}

/**
 * 类型切换
 **/
extension PreferencesApplicationViewController {

    private func setupModeControl() {
        modeControl.segmentCount = 2
        modeControl.setLabel(NSLocalizedString("overridesApplicationsSegment", comment: "Segment title for per-application overrides"), forSegment: OverridesMode.applications.rawValue)
        modeControl.setLabel(NSLocalizedString("overridesDevicesSegment", comment: "Segment title for per-device overrides"), forSegment: OverridesMode.devices.rawValue)
        modeControl.segmentStyle = .rounded
        modeControl.controlSize = .small
        modeControl.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        modeControl.trackingMode = .selectOne
        modeControl.selectedSegment = mode.rawValue
        modeControl.target = self
        modeControl.action = #selector(modeControlChange(_:))
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(modeControl)
        // 表头与空状态视图在 Storyboard 中已为切换控件预留顶部空间
        NSLayoutConstraint.activate([
            modeControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            modeControl.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
        ])
    }

    @objc private func modeControlChange(_ sender: NSSegmentedControl) {
        guard let nextMode = OverridesMode(rawValue: sender.selectedSegment), nextMode != mode else { return }
        mode = nextMode
        tableView.deselectAll(nil)
        tableView.reloadData()
        syncViewWithOptions()
        toggleNoDataHint()
        updateDelButtonState()
    }

    /// 按当前类型切换文案; 应用文案沿用 Storyboard 中的本地化结果
    private func updateModeTexts() {
        switch mode {
        case .applications:
            for (field, text) in applicationTexts { field.stringValue = text }
            tableEmptyImage?.image = applicationEmptyImage
        case .devices:
            tableHeadTitle?.stringValue = NSLocalizedString("overridesDeviceColumn", comment: "Column title of the per-device overrides list")
            tableEmptyTitle?.stringValue = NSLocalizedString("overridesNoDeviceTitle", comment: "Empty state title of the per-device overrides list")
            tableEmptyDescription?.stringValue = NSLocalizedString("overridesNoDeviceDescription", comment: "Empty state description of the per-device overrides list")
            createButtonTitle?.stringValue = NSLocalizedString("overridesAddDevice", comment: "Primary button title to add a per-device override")
            createButtonDescription?.stringValue = NSLocalizedString("overridesAddDeviceDescription", comment: "Primary button description to add a per-device override")
            if let image = PreferencesApplicationViewController.deviceIcon(pointSize: 44) {
                tableEmptyImage?.image = image
            }
        }
    }

    static func deviceIcon(pointSize: CGFloat? = nil) -> NSImage? {
        if #available(macOS 11.0, *) {
            let image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: nil)
            guard let pointSize = pointSize else { return image }
            return image?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .ultraLight))
        }
        return NSImage(named: NSImage.computerName)
    }
}

/**
 * 数据持久化
 **/
extension PreferencesApplicationViewController {
    // 同步界面与设置参数
    func syncViewWithOptions() {
        // 白名单: 应用与设备各自独立; 说明弹窗内容仅针对应用
        let allowlist = mode == .applications ? Options.shared.application.allowlist : Options.shared.device.allowlist
        allowlistModeCheckBox.state = NSControl.StateValue(rawValue: allowlist ? 1 : 0)
        allowlistModeCheckBox.toolTip = mode == .applications ? nil : NSLocalizedString("overridesDeviceAllowlistTooltip", comment: "Tooltip of the allow list checkbox in the device list")
        updateModeTexts()
    }

    // 更新删除按钮状态
    func updateDelButtonState() {
        delButton.isEnabled = tableView.selectedRow != -1
    }
}

/**
 * 表格区域渲染及操作
 **/
extension PreferencesApplicationViewController: NSTableViewDelegate, NSTableViewDataSource {
    // 每一列在 Storybroad 中的 identifier
    fileprivate enum CellIdentifiers {
        static let enabledCell = "enabledCell"
        static let applicationCell = "applicationCell"
        static let scrollingCell = "scrollingCell"
    }
    private static let enabledColumnWidth: CGFloat = 30

    /// 行首的启用开关单独成列 (Storyboard 只定义了应用与滚动两列)
    private func setupEnabledColumn() {
        let width = PreferencesApplicationViewController.enabledColumnWidth
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(CellIdentifiers.enabledCell))
        column.width = width
        column.minWidth = width
        column.maxWidth = width
        column.resizingMask = []
        tableView.addTableColumn(column)
        tableView.moveColumn(tableView.numberOfColumns - 1, toColumn: 0)
        // 总宽度不变: 从应用列中让出
        if let applicationColumn = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(CellIdentifiers.applicationCell)) {
            applicationColumn.width -= width
        }
    }

    /// 表头标题与应用/设备图标左对齐 (图标在单元格内的边距为 Storyboard 中的 20)
    private func alignTableHeadTitle() {
        let applicationColumn = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier(CellIdentifiers.applicationCell))
        guard let title = tableHeadTitle, let container = title.superview, applicationColumn >= 0,
              let leading = container.constraints.first(where: { $0.firstItem === title && $0.firstAttribute == .leading }) else {
            return
        }
        let iconX = tableView.convert(tableView.rect(ofColumn: applicationColumn), to: container).minX + 20
        if abs(leading.constant - iconX) > 0.5 {
            leading.constant = iconX
        }
    }

    /// 刷新某行的所有列 (名称, 摘要, 启用开关)
    func reloadRow(_ row: Int) {
        tableView.reloadData(forRowIndexes: [row], columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
    }
    private var currentItemCount: Int {
        switch mode {
        case .applications: return Options.shared.application.applications.count
        case .devices: return Options.shared.device.devices.count
        }
    }
    // 切换无数据显示
    func toggleNoDataHint() {
        let hasData = currentItemCount != 0
        updateViewVisibility(view: createButton, visible: !hasData)
        updateViewVisibility(view: tableEmpty, visible: !hasData)
        updateViewVisibility(view: tableHead, visible: hasData)
        updateViewVisibility(view: tableFoot, visible: hasData)
    }
    private func updateViewVisibility(view: NSView, visible: Bool) {
        view.isHidden = !visible
        view.animator().alphaValue = visible ? 1 : 0
    }
    // 点击设置
    @objc func settingScrollingButtonClick(_ sender: NSButton!) {
        // 行号
        let row = sender.tag
        // 从 SB 构建内容
        let scrollingWithApplicationViewController = Utils.instantiateControllerFromStoryboard(withIdentifier: PANEL_IDENTIFIER.scrollingWithApplication) as PreferencesScrollingWithApplicationViewController
        // 更新目标数据
        switch mode {
        case .applications:
            scrollingWithApplicationViewController.updateTargetApplication(with: Options.shared.application.applications.get(by: row))
        case .devices:
            scrollingWithApplicationViewController.updateTargetDevice(with: Options.shared.device.devices.get(by: row))
        }
        scrollingWithApplicationViewController.updateParentData(with: tableView, for: row)
        // 关闭后刷新该行的覆盖摘要
        scrollingWithApplicationViewController.onClose = { [weak self] in
            guard let self = self, row < self.currentItemCount else { return }
            self.reloadRow(row)
        }
        // 展示到指定位置
        present(scrollingWithApplicationViewController, asPopoverRelativeTo: sender.bounds, of: sender, preferredEdge: NSRectEdge.maxX, behavior: NSPopover.Behavior.transient)
    }
    // 构建表格数据 (循环生成行)
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        // 启用开关列没有 Storyboard 原型, 需在 makeView 之前单独处理
        if tableColumn?.identifier.rawValue == CellIdentifiers.enabledCell {
            return enabledCell(row: row)
        }
        guard let tableColumnIdentifier = tableColumn?.identifier,
              let cell = tableView.makeView(withIdentifier: tableColumnIdentifier, owner: self) as? NSTableCellView else {
            return nil
        }
        // 生成每行的 Cell
        switch tableColumnIdentifier.rawValue {
            // 应用 / 设备
            case CellIdentifiers.applicationCell:
                switch mode {
                case .applications:
                    guard let application = Options.shared.application.applications.get(by: row) else { return nil }
                    cell.imageView?.image = application.getIcon()
                    cell.imageView?.toolTip = application.path
                    cell.textField?.attributedStringValue = PreferencesApplicationViewController.title(application.getName(), summary: PreferencesApplicationViewController.overrideSummary(for: application), disabled: application.disabled)
                case .devices:
                    guard let device = Options.shared.device.devices.get(by: row) else { return nil }
                    cell.imageView?.image = PreferencesApplicationViewController.deviceIcon()
                    cell.imageView?.toolTip = device.identity
                    cell.textField?.attributedStringValue = PreferencesApplicationViewController.title(device.getName(), summary: PreferencesApplicationViewController.overrideSummary(for: device), disabled: device.disabled)
                }
                return cell
            // 设定: 滚动
            case CellIdentifiers.scrollingCell:
                let button = cell.subviews[0] as! NSButton
                button.tag = row
                button.target = self
                button.action = #selector(settingScrollingButtonClick)
                return cell
            default: break
        }
        return nil
    }
    /// 名称 + 覆盖摘要 (次要文字色); 停用时名称变灰, 摘要显示为已停用
    private static func title(_ name: String, summary: String, disabled: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString(string: name, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: disabled ? NSColor.disabledControlTextColor : NSColor.controlTextColor,
        ])
        let detail = disabled ? NSLocalizedString("overridesSummaryDisabled", comment: "Summary for an override entry where Mos is turned off") : summary
        result.append(NSAttributedString(string: "  " + detail, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        return result
    }
    /// 启用开关单元格 (代码创建, 按列标识复用)
    private func enabledCell(row: Int) -> NSView {
        let identifier = NSUserInterfaceItemIdentifier(CellIdentifiers.enabledCell)
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let checkBox = NSButton(checkboxWithTitle: "", target: self, action: #selector(entryEnabledClick(_:)))
            checkBox.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(checkBox)
            NSLayoutConstraint.activate([
                checkBox.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                checkBox.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        guard let checkBox = cell.subviews.first as? NSButton else { return cell }
        let disabled: Bool
        switch mode {
        case .applications: disabled = Options.shared.application.applications.get(by: row)?.disabled ?? false
        case .devices: disabled = Options.shared.device.devices.get(by: row)?.disabled ?? false
        }
        checkBox.tag = row
        checkBox.state = disabled ? .off : .on
        checkBox.toolTip = mode == .applications
            ? NSLocalizedString("overridesEnableApplicationTooltip", comment: "Tooltip of the checkbox that turns Mos on or off for an application")
            : NSLocalizedString("overridesEnableDeviceTooltip", comment: "Tooltip of the checkbox that turns Mos on or off for a device")
        return cell
    }

    @objc private func entryEnabledClick(_ sender: NSButton) {
        let row = sender.tag
        let disabled = sender.state == .off
        switch mode {
        case .applications:
            Options.shared.application.applications.get(by: row)?.disabled = disabled
        case .devices:
            Options.shared.device.devices.get(by: row)?.disabled = disabled
        }
        reloadRow(row)
    }

    // 行高
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 30
    }
    // 行数
    func numberOfRows(in tableView: NSTableView) -> Int {
        return currentItemCount
    }

    // 选择变化
    func tableViewSelectionDidChange(_ notification: Notification) {
        updateDelButtonState()
    }
}



/**
 * 应用添加/删除控制
 */
extension PreferencesApplicationViewController: NSMenuDelegate {

    // 打开文件选择窗口
    func openFileSelectionPanel() {
        let openPanel = NSOpenPanel()
        // 默认打开的目录 (/Application)
        openPanel.directoryURL = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first!
        // 禁止选择文件夹
        openPanel.canChooseDirectories = false
        // 允许选择文件
        openPanel.canChooseFiles = true
        // 不允许复数选择
        openPanel.allowsMultipleSelection = false
        // 允许的文件类型
        // openPanel.allowedFileTypes = ["app", "App", "APP"]
        // 打开文件选择窗口并读取文件添加到 Applications 列表中
        openPanel.beginSheetModal(for: view.window!, completionHandler: { result in
            if result.rawValue == NSApplication.ModalResponse.OK.rawValue && result == NSApplication.ModalResponse.OK {
                // 根据路径获取 application 信息并保存到 Applications 列表中
                if let bundlePath = openPanel.url?.path {
                    self.appendApplicationWith(path: bundlePath)
                }
            }
        })
    }

    // 初始化菜单
    func openRunningApplicationPanel(_ targetView: NSView, _ targetPosition: NSPoint) {
        // 清除已有
        runningAndInstalledMenuChildrenContainer.removeAllItems()
        // 初始化 Running 应用
        for runningApplication in NSWorkspace.shared.runningApplications {
            guard runningApplication.activationPolicy == .regular else { continue }
            let icon = Utils.getApplicationIcon(fromPath: runningApplication.bundleURL?.path)
            let name = Utils.getApplicationName(fromPath: runningApplication.executableURL?.path)
            let isExist = ScrollUtils.shared.getTargetApplication(from: runningApplication) !== nil
            Utils.addMenuItem(
                to: runningAndInstalledMenuChildrenContainer,
                title: name,
                icon: icon,
                action: #selector(appendApplicationWithRunningApplication),
                target: isExist ? nil : self,
                represent: runningApplication
            )
        }
        // 显示菜单
        applicationSourceMenuControl.popUp(positioning: nil, at: targetPosition, in: targetView)
    }

    // 添加应用
    func appendApplicationWith(path: String) {
        let application = Application(path: path)
        Options.shared.application.applications.append(application)
        tableView.reloadData()
        toggleNoDataHint()
    }
    @objc func appendApplicationWithRunningApplication(_ sender: NSMenuItem!) {
        guard let runningApplication = sender.representedObject as? NSRunningApplication else { return }
        guard let executablePath = runningApplication.executableURL?.path else { return }
        appendApplicationWith(path: executablePath)
    }

    // 已连接的鼠标菜单 (最近滚动过的排在最前, 已添加的不可选)
    func openConnectedDevicePanel(_ targetView: NSView, _ targetPosition: NSPoint) {
        deviceSourceMenu.removeAllItems()
        var infos = PointingDeviceRegistry.shared.connectedMice()
        if let last = PointingDeviceRegistry.shared.lastScrollDevice {
            infos.removeAll { $0.identity == last.identity }
            infos.insert(last, at: 0)
        }
        if infos.isEmpty {
            let item = deviceSourceMenu.addItem(withTitle: NSLocalizedString("scrollDevicesNone", comment: "Shown when no mouse is connected"), action: nil, keyEquivalent: "")
            item.isEnabled = false
        }
        for info in infos {
            let isExist = Options.shared.device.devices.get(by: info.identity) != nil
            let item = Utils.addMenuItem(
                to: deviceSourceMenu,
                title: info.name.isEmpty ? info.identity : info.name,
                icon: PreferencesApplicationViewController.deviceIcon(),
                action: #selector(appendDeviceWithConnectedDevice),
                target: isExist ? nil : self,
                represent: info.identity
            )
            item.toolTip = info.identity
        }
        deviceMenuInfos = Dictionary(infos.map { ($0.identity, $0) }, uniquingKeysWith: { first, _ in first })
        deviceSourceMenu.popUp(positioning: nil, at: targetPosition, in: targetView)
    }

    @objc func appendDeviceWithConnectedDevice(_ sender: NSMenuItem!) {
        guard let identity = sender.representedObject as? String,
              let info = deviceMenuInfos[identity],
              Options.shared.device.devices.get(by: identity) == nil else { return }
        Options.shared.device.devices.append(ScrollDevice(info: info))
        tableView.reloadData()
        toggleNoDataHint()
    }
}

/**
 * 覆盖摘要: 列出与全局不同的设定项及其取值, 如 "Smooth: Off, Speed: 5.00"
 **/
extension PreferencesApplicationViewController {

    static func overrideSummary(for profile: ScrollProfile) -> String {
        let differing = profile.differingSettings()
        if differing.isEmpty {
            return NSLocalizedString("overridesSummaryNone", comment: "Summary for an override entry that inherits every setting")
        }
        let values = profile.effectiveValues()
        let global = ScrollOptionsResolver.resolve(global: Options.shared.scroll, layers: [])
        let format = NSLocalizedString("overridesSummaryItemFormat", comment: "One item in the override summary: setting name, then its value, e.g. \"Smooth: Off\"")
        let separator = NSLocalizedString("overridesSummarySeparator", comment: "Separator between setting names in the override summary")
        return ScrollSetting.allCases.filter { differing.contains($0) }.map { setting in
            String(format: format, name(of: setting), value(of: setting, in: values, global: global))
        }.joined(separator: separator)
    }

    private static func name(of setting: ScrollSetting) -> String {
        switch setting {
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

    private static func value(of setting: ScrollSetting, in values: ScrollValues, global: ScrollValues) -> String {
        switch setting {
        case .smooth:
            // 总开关相同时, 差异在细节 (轴向 / 模拟触控板) 中
            return values.smooth == global.smooth ? customValue : onOff(values.smooth)
        case .reverse:
            return values.reverse == global.reverse ? customValue : onOff(values.reverse)
        case .dash: return hotkeyName(values.dash)
        case .toggle: return hotkeyName(values.toggle)
        case .block: return hotkeyName(values.block)
        case .step: return String(format: "%.2f", values.step)
        case .speed: return String(format: "%.2f", values.speed)
        case .duration: return String(format: "%.2f", values.duration)
        }
    }

    private static func onOff(_ isOn: Bool) -> String {
        return isOn
            ? NSLocalizedString("overridesSummaryValueOn", comment: "Value 'on' in the override summary")
            : NSLocalizedString("overridesSummaryValueOff", comment: "Value 'off' in the override summary")
    }

    private static var customValue: String {
        return NSLocalizedString("overridesSummaryValueCustom", comment: "Value in the override summary when only detail options (axes etc.) differ")
    }

    private static func hotkeyName(_ hotkey: ScrollHotkey?) -> String {
        guard let hotkey = hotkey else {
            return NSLocalizedString("Disabled", comment: "Hotkey disabled state")
        }
        return PreferencesScrollingViewController.getFullDisplayName(for: hotkey)
    }
}
