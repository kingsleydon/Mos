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
    private let device = ScrollDevice(vendorID: 0x19f5, productID: 0x3246, name: "NuPhy Air75 V2")
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
        // 设备: 关闭翻转
        Options.shared.device.devices.append(device)
        device.beginOverriding([.reverse])
        device.scroll.reverse = false
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

    private func snapshot(_ controller: NSViewController, name: String) {
        let window = NSWindow(contentViewController: controller)
        window.appearance = NSAppearance(named: .darkAqua)
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFrontRegardless()
        windows.append(window)
        // 等待异步布局 (表头对齐等) 完成
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let view = controller.view
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            XCTFail("cannot render \(name)")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        let url = outputDirectory.appendingPathComponent("\(name).png")
        XCTAssertNoThrow(try rep.representation(using: .png, properties: [:])?.write(to: url))
    }
}
