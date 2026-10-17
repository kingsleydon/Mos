//
//  ScrollProfileResolutionTests.swift
//  MosTests
//
//  按设定项继承 (例外应用 / 例外设备) 的解析, 迁移与持久化
//

import XCTest
@testable import Mos_Debug

final class ScrollProfileResolutionTests: XCTestCase {

    // 仅快照本测试会改动的全局字段 (OPTIONS_SCROLL_DEFAULT 是 class, 引用快照无法回滚变更)
    private var savedGlobal: ScrollValues!

    override func setUp() {
        super.setUp()
        savedGlobal = Options.shared.scroll.values
    }

    override func tearDown() {
        let global = Options.shared.scroll
        global.smooth = savedGlobal.smooth
        global.smoothSimTrackpad = savedGlobal.smoothSimTrackpad
        global.reverse = savedGlobal.reverse
        global.reverseVertical = savedGlobal.reverseVertical
        global.step = savedGlobal.step
        global.speed = savedGlobal.speed
        global.duration = savedGlobal.duration
        global.dash = savedGlobal.dash
        super.tearDown()
    }

    private func makeApplication() -> Application {
        return Application(path: "/Applications/ScrollProfileTest.app")
    }

    private func makeDevice() -> ScrollDevice {
        return ScrollDevice(vendorID: 0x046d, productID: 0xb034, name: "MX Master 3S")
    }

    // MARK: - 按设定项继承

    func testOverriddenSettingIgnoresGlobalWhileOthersFollowIt() {
        Options.shared.scroll.reverse = true
        Options.shared.scroll.smooth = true
        let application = makeApplication()
        application.beginOverriding([.reverse])
        application.scroll.reverse = false

        // 覆盖的设定项使用应用自身配置
        XCTAssertFalse(application.isReverse())
        // 未覆盖的设定项继续跟随全局
        XCTAssertTrue(application.isSmooth(false))
        Options.shared.scroll.smooth = false
        XCTAssertFalse(application.isSmooth(false), "inherited setting must follow later global changes")
        Options.shared.scroll.reverse = true
        XCTAssertFalse(application.isReverse(), "overridden setting must not follow later global changes")
    }

    func testBeginOverridingMaterializesCurrentEffectiveValue() {
        Options.shared.scroll.step = 12.5
        let application = makeApplication()
        application.scroll.step = 99
        application.beginOverriding([.step])

        XCTAssertEqual(application.scroll.step, 12.5, "overriding must start from the value the user was seeing")
        XCTAssertEqual(application.getStep(), 12.5)
    }

    func testInheritRestoresGlobalValue() {
        Options.shared.scroll.speed = 3
        let application = makeApplication()
        application.beginOverriding([.speed])
        application.scroll.speed = 7
        XCTAssertEqual(application.getSpeed(), 7)

        application.inherit([.speed])
        XCTAssertEqual(application.getSpeed(), 3)
    }

    func testLegacyInheritFlagMapsToAllOrNothing() {
        let application = makeApplication()
        application.inherit = false
        XCTAssertEqual(application.overrides, Set(ScrollSetting.allCases))
        application.inherit = true
        XCTAssertTrue(application.overrides.isEmpty)
        application.overrides = [.reverse]
        XCTAssertFalse(application.inherit, "partially overridden profile is not fully inheriting")
    }

    func testHotkeysResolvePerSetting() {
        Options.shared.scroll.dash = ScrollHotkey(type: .keyboard, code: KeyCode.optionL)
        let application = makeApplication()
        application.beginOverriding([.toggle])
        application.scroll.toggle = nil

        XCTAssertEqual(ScrollUtils.shared.optionsDashKey(application: application), Options.shared.scroll.dash)
        XCTAssertNil(ScrollUtils.shared.optionsToggleKey(application: application))
    }

    // MARK: - 例外设备

    func testDeviceOverridesTakePrecedenceOverApplication() {
        Options.shared.scroll.reverse = true
        let application = makeApplication()
        application.beginOverriding([.reverse, .step])
        application.scroll.reverse = true
        application.scroll.step = 20
        let device = makeDevice()
        device.beginOverriding([.reverse])
        device.scroll.reverse = false

        let resolved = ScrollOptionsResolver.resolve(application: application, device: device)
        XCTAssertFalse(resolved.reverse, "device override wins over the application override")
        XCTAssertEqual(resolved.step, 20, "settings the device does not override still come from the application")
    }

    func testDeviceCannotOverrideHotkeys() {
        let device = makeDevice()
        device.beginOverriding([.dash, .smooth])
        XCTAssertEqual(device.overrides, [.smooth])
    }

    func testSimulateTrackpadLocksDurationAcrossLayers() {
        Options.shared.scroll.duration = 2
        Options.shared.scroll.smoothSimTrackpad = false
        let device = makeDevice()
        device.beginOverriding([.smooth])
        device.scroll.smoothSimTrackpad = true

        let resolved = ScrollOptionsResolver.resolve(application: nil, device: device)
        XCTAssertEqual(resolved.duration, ScrollDurationLimits.simulateTrackpadDefault)
    }

    func testDeviceIdentityIsVendorAndProduct() {
        XCTAssertEqual(makeDevice().identity, "046d:b034")
    }

    func testVisibleValuesIgnoreSubDisplayDifferences() {
        Options.shared.scroll.step = 33.6
        let application = makeApplication()
        application.beginOverriding([.step])
        application.scroll.step = 33.6000001 // 滑块拖回 "33.60"
        let effective = ScrollOptionsResolver.resolve(global: Options.shared.scroll, layers: [application])
        let global = ScrollOptionsResolver.resolve(global: Options.shared.scroll, layers: [])
        XCTAssertNotEqual(effective, global)
        XCTAssertEqual(effective.visible, global.visible, "values that display the same must count as equal to global")
        application.scroll.step = 33.7
        XCTAssertNotEqual(ScrollOptionsResolver.resolve(global: Options.shared.scroll, layers: [application]).visible, global.visible)
    }

    // MARK: - 停用与白名单

    func testUnlistedEntriesFollowAllowlistMode() {
        XCTAssertTrue(ScrollOptionsResolver.isActive(application: nil, device: nil, applicationAllowlist: false, deviceAllowlist: false))
        XCTAssertFalse(ScrollOptionsResolver.isActive(application: nil, device: nil, applicationAllowlist: true, deviceAllowlist: false))
        XCTAssertFalse(ScrollOptionsResolver.isActive(application: nil, device: nil, applicationAllowlist: false, deviceAllowlist: true))
    }

    func testDisabledEntryTurnsMosOff() {
        let application = makeApplication()
        let device = makeDevice()
        XCTAssertTrue(ScrollOptionsResolver.isActive(application: application, device: device, applicationAllowlist: true, deviceAllowlist: true))
        device.disabled = true
        XCTAssertFalse(ScrollOptionsResolver.isActive(application: application, device: device, applicationAllowlist: false, deviceAllowlist: false), "a disabled device wins over an enabled app")
        device.disabled = false
        application.disabled = true
        XCTAssertFalse(ScrollOptionsResolver.isActive(application: application, device: device, applicationAllowlist: false, deviceAllowlist: false), "a disabled app wins over an enabled device")
    }

    func testDisabledFlagRoundTrip() throws {
        let application = makeApplication()
        application.disabled = true
        let device = makeDevice()
        device.disabled = true
        XCTAssertTrue(try JSONDecoder().decode(Application.self, from: JSONEncoder().encode(application)).disabled)
        XCTAssertTrue(try JSONDecoder().decode(ScrollDevice.self, from: JSONEncoder().encode(device)).disabled)
        let legacy = #"{"path":"/Applications/A.app","inherit":true}"#
        XCTAssertFalse(try JSONDecoder().decode(Application.self, from: Data(legacy.utf8)).disabled)
    }

    // MARK: - 持久化

    func testLegacyApplicationJSONDecodesToAllOrNothing() throws {
        let legacyOff = #"{"path":"/Applications/A.app","inherit":false}"#
        let legacyOn = #"{"path":"/Applications/B.app","inherit":true}"#
        let off = try JSONDecoder().decode(Application.self, from: Data(legacyOff.utf8))
        let on = try JSONDecoder().decode(Application.self, from: Data(legacyOn.utf8))
        XCTAssertEqual(off.overrides, Set(ScrollSetting.allCases))
        XCTAssertTrue(on.overrides.isEmpty)
    }

    func testApplicationRoundTripKeepsPerSettingOverrides() throws {
        let application = makeApplication()
        application.beginOverriding([.reverse, .speed])
        let data = try JSONEncoder().encode(application)
        let decoded = try JSONDecoder().decode(Application.self, from: data)
        XCTAssertEqual(decoded.overrides, [.reverse, .speed])
        // 旧版仍能读到整体开关
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["inherit"] as? Bool, false)
    }

    func testDeviceRoundTrip() throws {
        let device = makeDevice()
        device.beginOverriding([.reverse])
        device.scroll.reverse = false
        let data = try JSONEncoder().encode([device])
        let decoded = try JSONDecoder().decode([ScrollDevice].self, from: data)
        XCTAssertEqual(decoded.first?.identity, "046d:b034")
        XCTAssertEqual(decoded.first?.overrides, [.reverse])
        XCTAssertEqual(decoded.first?.scroll.reverse, false)
        XCTAssertEqual(decoded.first?.name, "MX Master 3S")
    }

    func testUnknownOverrideKeysAreIgnored() throws {
        let json = #"{"vendorID":1,"productID":2,"overrides":["reverse","fromTheFuture"]}"#
        let device = try JSONDecoder().decode(ScrollDevice.self, from: Data(json.utf8))
        XCTAssertEqual(device.overrides, [.reverse])
    }
}
