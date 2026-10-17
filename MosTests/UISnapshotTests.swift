//
//  UISnapshotTests.swift
//  MosTests
//
//  渲染偏好设置界面为 PNG (深色外观), 供人工检查布局. 不做像素比对.
//  输出目录: /tmp/MosSnapshots
//

import XCTest
@testable import Mos_Debug

final class UISnapshotTests: XCTestCase {

    private let outputDirectory = URL(fileURLWithPath: "/tmp/MosSnapshots", isDirectory: true)
    private let applicationPaths = ["/System/Library/CoreServices/Finder.app", "/System/Applications/Calendar.app", "/System/Applications/Notes.app"]
    private let device = ScrollDevice(vendorID: 0x046d, productID: 0xb037, name: "MX Anywhere 3S")
    private let disabledDevice = ScrollDevice(vendorID: 0x3299, productID: 0x4e6b, name: "ProtoArc Keyboard Touchpad")
    private var savedReverse = true
    private var windows: [NSWindow] = []

    override func setUp() {
        super.setUp()
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        savedReverse = Options.shared.scroll.reverse
        Options.shared.scroll.reverse = true
    }

    override func tearDown() {
        for path in applicationPaths {
            Options.shared.application.applications.remove(from: path)
        }
        Options.shared.device.devices.remove(from: device.identity)
        Options.shared.device.devices.remove(from: disabledDevice.identity)
        Options.shared.scroll.reverse = savedReverse
        windows.forEach { $0.close() }
        windows = []
        super.tearDown()
    }

    // MARK: - 场景

    func testSnapshotOverridesApplications() {
        addFixtures()
        let controller = makeOverridesController()
        snapshot(controller, name: "overrides-applications")
    }

    func testSnapshotOverridesDevices() {
        addFixtures()
        let controller = makeOverridesController()
        selectSegment(1, in: controller)
        snapshot(controller, name: "overrides-devices")
    }

    func testSnapshotOverridesDevicesEmpty() {
        let controller = makeOverridesController()
        selectSegment(1, in: controller)
        snapshot(controller, name: "overrides-devices-empty")
    }

    func testSnapshotApplicationPopover() {
        addFixtures()
        let controller = Utils.instantiateControllerFromStoryboard(withIdentifier: PANEL_IDENTIFIER.scrollingWithApplication) as PreferencesScrollingWithApplicationViewController
        controller.updateTargetApplication(with: Options.shared.application.applications.get(by: applicationPaths[1]))
        snapshot(controller, name: "popover-application-overridden")
    }

    func testSnapshotApplicationPopoverInheriting() {
        addFixtures()
        let controller = Utils.instantiateControllerFromStoryboard(withIdentifier: PANEL_IDENTIFIER.scrollingWithApplication) as PreferencesScrollingWithApplicationViewController
        controller.updateTargetApplication(with: Options.shared.application.applications.get(by: applicationPaths[0]))
        snapshot(controller, name: "popover-application-inheriting")
    }

    func testSnapshotDevicePopover() {
        addFixtures()
        let controller = Utils.instantiateControllerFromStoryboard(withIdentifier: PANEL_IDENTIFIER.scrollingWithApplication) as PreferencesScrollingWithApplicationViewController
        controller.updateTargetDevice(with: device)
        snapshot(controller, name: "popover-device")
    }

    func testSnapshotGlobalScrolling() {
        let controller = Utils.instantiateControllerFromStoryboard(withIdentifier: PANEL_IDENTIFIER.scrolling) as PreferencesScrollingViewController
        snapshot(controller, name: "scrolling-global")
    }

    // MARK: - 工具

    private func addFixtures() {
        // Finder: 全部继承; Calendar: 覆盖翻转与速度; Notes: 停用
        Options.shared.application.applications.append(Application(path: applicationPaths[0]))
        let calendar = Application(path: applicationPaths[1])
        Options.shared.application.applications.append(calendar)
        calendar.beginOverriding([.reverse, .speed])
        calendar.scroll.reverse = false
        calendar.scroll.speed = 5
        let disabled = Application(path: applicationPaths[2])
        Options.shared.application.applications.append(disabled)
        disabled.disabled = true
        // 设备: 鼠标关闭翻转; 带触摸板的键盘停用 Mos
        Options.shared.device.devices.append(device)
        device.beginOverriding([.reverse])
        device.scroll.reverse = false
        Options.shared.device.devices.append(disabledDevice)
        disabledDevice.disabled = true
    }

    private func makeOverridesController() -> PreferencesApplicationViewController {
        return Utils.instantiateControllerFromStoryboard(withIdentifier: PANEL_IDENTIFIER.application) as PreferencesApplicationViewController
    }

    private func selectSegment(_ index: Int, in controller: NSViewController) {
        _ = controller.view
        guard let segmented = controller.view.subviews.compactMap({ $0 as? NSSegmentedControl }).first,
              let action = segmented.action else {
            XCTFail("segmented control not found")
            return
        }
        segmented.selectedSegment = index
        NSApp.sendAction(action, to: segmented.target, from: segmented)
    }

    /// 深色与浅色外观各渲染一张
    private func snapshot(_ controller: NSViewController, name: String) {
        if #available(macOS 10.14, *) {
            render(controller, name: "\(name)-dark", appearance: NSAppearance(named: .darkAqua))
            render(controller, name: "\(name)-light", appearance: NSAppearance(named: .aqua))
        } else {
            render(controller, name: name, appearance: nil)
        }
    }

    private func render(_ controller: NSViewController, name: String, appearance: NSAppearance?) {
        // 同一控制器复用时先移出上一个窗口
        windows.last?.contentViewController = nil
        let window = NSWindow(contentViewController: controller)
        window.appearance = appearance
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFrontRegardless()
        windows.append(window)
        // 等待异步布局 (表头对齐等) 完成
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let view = controller.view
        view.layoutSubtreeIfNeeded()
        // 2x 渲染, 便于在文档中清晰展示
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(view.bounds.width * scale),
            pixelsHigh: Int(view.bounds.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else {
            XCTFail("cannot render \(name)")
            return
        }
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        let url = outputDirectory.appendingPathComponent("\(name).png")
        XCTAssertNoThrow(try rep.representation(using: .png, properties: [:])?.write(to: url))
    }
}
