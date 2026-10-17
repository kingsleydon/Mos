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

    /// 滚动路径实际使用的解析结果 (全局 → 应用)
    private func resolved(_ application: Application) -> ScrollValues {
        return ScrollOptionsResolver.resolve(application: application, device: nil)
    }

    // MARK: - 按设定项继承

    func testOverriddenSettingIgnoresGlobalWhileOthersFollowIt() {
        Options.shared.scroll.reverse = true
        Options.shared.scroll.smooth = true
        let application = makeApplication()
        application.beginOverriding([.reverse])
        application.scroll.reverse = false

        // 覆盖的设定项使用应用自身配置
        XCTAssertFalse(resolved(application).reverse)
        // 未覆盖的设定项继续跟随全局
        XCTAssertTrue(resolved(application).isSmooth(false))
        Options.shared.scroll.smooth = false
        XCTAssertFalse(resolved(application).isSmooth(false), "inherited setting must follow later global changes")
        Options.shared.scroll.reverse = true
        XCTAssertFalse(resolved(application).reverse, "overridden setting must not follow later global changes")
    }

    func testBeginOverridingMaterializesCurrentEffectiveValue() {
        Options.shared.scroll.step = 12.5
        let application = makeApplication()
        application.scroll.step = 99
        application.beginOverriding([.step])

        XCTAssertEqual(application.scroll.step, 12.5, "overriding must start from the value the user was seeing")
        XCTAssertEqual(resolved(application).step, 12.5)
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

    func testEditingBackToGlobalValueInheritsAgain() {
        Options.shared.scroll.reverse = true
        let application = makeApplication()
        application.beginOverriding([.reverse])
        application.scroll.reverse = false
        application.inheritSettingsMatchingGlobal([.reverse])
        XCTAssertEqual(application.overrides, [.reverse], "a value that differs from global stays overridden")
        application.scroll.reverse = true
        application.inheritSettingsMatchingGlobal([.reverse])
        XCTAssertTrue(application.overrides.isEmpty, "setting it back to the global value inherits again")
    }

    func testOverrideMatchingGlobalAfterGlobalChangeIsKeptButNotShown() {
        Options.shared.scroll.reverse = true
        let application = makeApplication()
        application.beginOverriding([.reverse])
        application.scroll.reverse = false
        XCTAssertEqual(application.differingSettings(), [.reverse])
        // 全局之后也改为关闭: 覆盖保留, 但界面视为一致
        Options.shared.scroll.reverse = false
        XCTAssertEqual(application.overrides, [.reverse])
        XCTAssertTrue(application.differingSettings().isEmpty)
        // 全局再改回开启: 覆盖重新生效
        Options.shared.scroll.reverse = true
        XCTAssertFalse(resolved(application).reverse)
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

    // MARK: - 持久化

    func testLegacyApplicationJSONDecodesToAllOrNothing() throws {
        let legacyOff = #"{"path":"/Applications/A.app","inherit":false}"#
        let legacyOn = #"{"path":"/Applications/B.app","inherit":true}"#
        let off = try JSONDecoder().decode(Application.self, from: Data(legacyOff.utf8))
        let on = try JSONDecoder().decode(Application.self, from: Data(legacyOn.utf8))
        XCTAssertEqual(off.overrides, Set(ScrollSetting.allCases))
        XCTAssertTrue(on.overrides.isEmpty)
        XCTAssertFalse(off.disabled, "legacy entries keep Mos enabled")
    }

    func testApplicationRoundTripKeepsPerSettingOverrides() throws {
        let application = makeApplication()
        application.beginOverriding([.reverse, .speed])
        application.disabled = true
        let data = try JSONEncoder().encode(application)
        let decoded = try JSONDecoder().decode(Application.self, from: data)
        XCTAssertEqual(decoded.overrides, [.reverse, .speed])
        XCTAssertTrue(decoded.disabled)
        // 旧版仍能读到整体开关
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["inherit"] as? Bool, false)
    }

    func testLegacyReaderSeesEffectiveValues() throws {
        // 旧版 Mos 读取: inherit=false 时整组使用 scroll
        Options.shared.scroll.speed = 7
        let application = makeApplication()
        application.beginOverriding([.reverse])
        application.scroll.reverse = false
        application.scroll.speed = 2.7 // 未覆盖字段中的过期本地值
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(application)) as? [String: Any]
        let scroll = object?["scroll"] as? [String: Any]
        XCTAssertEqual(object?["inherit"] as? Bool, false)
        XCTAssertEqual(scroll?["speed"] as? Double, 7, "inherited settings must be written as the current global value")
        XCTAssertEqual(scroll?["reverse"] as? Bool, false)
    }

    func testDeviceRoundTrip() throws {
        let device = makeDevice()
        device.beginOverriding([.reverse])
        device.scroll.reverse = false
        device.disabled = true
        let data = try JSONEncoder().encode([device])
        let decoded = try JSONDecoder().decode([ScrollDevice].self, from: data)
        XCTAssertEqual(decoded.first?.identity, "046d:b034")
        XCTAssertEqual(decoded.first?.overrides, [.reverse])
        XCTAssertEqual(decoded.first?.scroll.reverse, false)
        XCTAssertEqual(decoded.first?.name, "MX Master 3S")
        XCTAssertEqual(decoded.first?.disabled, true)
    }

    func testUnknownOverrideKeysAreIgnored() throws {
        let json = #"{"vendorID":1,"productID":2,"overrides":["reverse","fromTheFuture"]}"#
        let device = try JSONDecoder().decode(ScrollDevice.self, from: Data(json.utf8))
        XCTAssertEqual(device.overrides, [.reverse])
    }
}
