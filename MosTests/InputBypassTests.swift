//
//  InputBypassTests.swift
//  MosTests
//
//  停用 / 白名单: 完全忽略事件的判定
//

import XCTest
@testable import Mos_Debug

final class InputBypassTests: XCTestCase {

    private var savedApplicationAllowlist = false
    private var savedDeviceAllowlist = false

    override func setUp() {
        super.setUp()
        savedApplicationAllowlist = Options.shared.application.allowlist
        savedDeviceAllowlist = Options.shared.device.allowlist
        Options.shared.application.allowlist = false
        Options.shared.device.allowlist = false
    }

    override func tearDown() {
        Options.shared.application.allowlist = savedApplicationAllowlist
        Options.shared.device.allowlist = savedDeviceAllowlist
        super.tearDown()
    }

    private func makeKeyEvent() -> CGEvent {
        return CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
    }

    private func makeMouseEvent() -> CGEvent {
        return CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: .zero, mouseButton: .center)!
    }

    func testNothingBypassedByDefault() {
        XCTAssertFalse(InputBypass.shared.shouldBypass(makeKeyEvent(), isPointingEvent: false))
        XCTAssertFalse(InputBypass.shared.shouldBypass(makeMouseEvent(), isPointingEvent: true))
    }

    func testApplicationAllowlistBypassesUnlistedApplications() {
        // 测试进程 (或其前台应用) 不在列表中
        Options.shared.application.allowlist = true
        XCTAssertTrue(InputBypass.shared.shouldBypass(makeKeyEvent(), isPointingEvent: false))
        XCTAssertTrue(InputBypass.shared.shouldBypass(makeMouseEvent(), isPointingEvent: true))
    }

    func testDeviceAllowlistNeverBypassesKeyboardEvents() {
        // 键盘不在设备列表中; 设备白名单不得屏蔽键盘热键 (如 Option 加速键)
        Options.shared.device.allowlist = true
        XCTAssertFalse(InputBypass.shared.shouldBypass(makeKeyEvent(), isPointingEvent: false))
        // 合成的鼠标事件无法识别来源设备, 白名单下视为未列出
        XCTAssertTrue(InputBypass.shared.shouldBypass(makeMouseEvent(), isPointingEvent: true))
    }

    // MARK: - 按键过程配对

    func testBypassedPressAlsoBypassesItsRelease() {
        let tracker = BypassedPressTracker()
        Options.shared.application.allowlist = true
        XCTAssertTrue(tracker.shouldBypassDown(makeKeyEvent(), type: .keyDown))
        // 抬起前恢复处理: 抬起仍需跟随按下被忽略
        Options.shared.application.allowlist = false
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)!
        XCTAssertTrue(tracker.shouldBypassUp(up, type: .keyUp))
        XCTAssertFalse(tracker.shouldBypassUp(up, type: .keyUp), "each release pairs with one press")
    }

    func testReleaseOfProcessedPressIsNotBypassed() {
        let tracker = BypassedPressTracker()
        XCTAssertFalse(tracker.shouldBypassDown(makeKeyEvent(), type: .keyDown))
        // 按住时切换到被忽略的应用: 抬起仍要交给 Mos 释放
        Options.shared.application.allowlist = true
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)!
        XCTAssertFalse(tracker.shouldBypassUp(up, type: .keyUp))
    }

    func testAutorepeatDoesNotStartBypass() {
        let tracker = BypassedPressTracker()
        Options.shared.application.allowlist = true
        let repeatEvent = makeKeyEvent()
        repeatEvent.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        XCTAssertFalse(tracker.shouldBypassDown(repeatEvent, type: .keyDown), "repeats of a processed press keep going to Mos")
    }
}
