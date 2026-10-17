//
//  PointingDeviceRegistry.swift
//  Mos
//  识别滚动事件来源设备, 枚举已连接的鼠标
//

import Cocoa
import IOKit.hid

struct PointingDeviceInfo: Equatable {
    let vendorID: Int
    let productID: Int
    let name: String

    var identity: String {
        return ScrollDevice.identity(vendorID: vendorID, productID: productID)
    }
}

class PointingDeviceRegistry {

    // 单例
    static let shared = PointingDeviceRegistry()
    init() { NSLog("Module initialized: PointingDeviceRegistry") }

    // CGEvent 本身不携带设备信息; 通过私有 (但已导出) 的 SPI 取出底层 IOHIDEvent 的 senderID,
    // 即产生该事件的 IOHIDEventService 的 registry entry ID. 运行时按符号查找, 缺失时整体降级为不识别
    private typealias CopyIOHIDEventFunction = @convention(c) (CGEvent) -> OpaquePointer?
    private typealias GetSenderIDFunction = @convention(c) (OpaquePointer) -> UInt64
    private lazy var copyIOHIDEvent: CopyIOHIDEventFunction? = PointingDeviceRegistry.lookup("CGEventCopyIOHIDEvent")
    private lazy var getSenderID: GetSenderIDFunction? = PointingDeviceRegistry.lookup("IOHIDEventGetSenderID")

    // senderID → 设备信息 (nil 表示查询过但无法识别). 事件 tap 运行在主线程, 无需加锁
    private var senderCache: [UInt64: PointingDeviceInfo?] = [:]
    // 最近一次识别到的滚动设备, 供设置界面优先展示
    private(set) var lastScrollDevice: PointingDeviceInfo?

    private static func lookup<T>(_ symbol: String) -> T? {
        // RTLD_DEFAULT
        guard let handle = UnsafeMutableRawPointer(bitPattern: -2),
              let pointer = dlsym(handle, symbol) else {
            NSLog("PointingDeviceRegistry: symbol \(symbol) unavailable, device overrides disabled")
            return nil
        }
        return unsafeBitCast(pointer, to: T.self)
    }
}

/**
 * 事件来源识别
 **/
extension PointingDeviceRegistry {

    func senderID(of event: CGEvent) -> UInt64? {
        guard let copyIOHIDEvent = copyIOHIDEvent, let getSenderID = getSenderID else { return nil }
        // 合成事件 (如远程桌面, 其他工具) 没有底层 HID 事件
        guard let hidEvent = copyIOHIDEvent(event) else { return nil }
        defer { Unmanaged<CFTypeRef>.fromOpaque(UnsafeRawPointer(hidEvent)).release() }
        let senderID = getSenderID(hidEvent)
        return senderID == 0 ? nil : senderID
    }

    func device(for event: CGEvent) -> PointingDeviceInfo? {
        guard let senderID = senderID(of: event) else { return nil }
        let info: PointingDeviceInfo?
        if let cached = senderCache[senderID] {
            info = cached
        } else {
            info = PointingDeviceRegistry.deviceInfo(forRegistryEntryID: senderID)
            senderCache[senderID] = info
        }
        if let info = info {
            lastScrollDevice = info
        }
        return info
    }

    /// 自事件服务节点向上查找第一个带有 VendorID/ProductID 的节点
    static func deviceInfo(forRegistryEntryID entryID: UInt64) -> PointingDeviceInfo? {
        guard let matching = IORegistryEntryIDMatching(entryID) else { return nil }
        // IOServiceGetMatchingService 会消耗 matching 字典
        var entry = IOServiceGetMatchingService(mach_port_t(MACH_PORT_NULL), matching)
        while entry != 0 {
            if let info = deviceInfo(forEntry: entry) {
                IOObjectRelease(entry)
                return info
            }
            var parent: io_registry_entry_t = 0
            let result = IORegistryEntryGetParentEntry(entry, "IOService", &parent)
            IOObjectRelease(entry)
            guard result == KERN_SUCCESS else { break }
            entry = parent
        }
        return nil
    }

    private static func deviceInfo(forEntry entry: io_registry_entry_t) -> PointingDeviceInfo? {
        guard let vendorID = intProperty(entry, kIOHIDVendorIDKey),
              let productID = intProperty(entry, kIOHIDProductIDKey) else {
            return nil
        }
        let name = stringProperty(entry, kIOHIDProductKey) ?? ""
        return PointingDeviceInfo(vendorID: vendorID, productID: productID, name: name)
    }

    private static func intProperty(_ entry: io_registry_entry_t, _ key: String) -> Int? {
        let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        return (value as? NSNumber)?.intValue
    }

    private static func stringProperty(_ entry: io_registry_entry_t, _ key: String) -> String? {
        let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        return value as? String
    }
}

/**
 * 已连接设备枚举 (仅读取 IORegistry, 无需输入监控权限)
 **/
extension PointingDeviceRegistry {

    func connectedMice() -> [PointingDeviceInfo] {
        guard let matching = IOServiceMatching(kIOHIDDeviceKey) else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(mach_port_t(MACH_PORT_NULL), matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [PointingDeviceInfo] = []
        var seen = Set<String>()
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            guard PointingDeviceRegistry.isExternalMouse(entry),
                  let info = PointingDeviceRegistry.deviceInfo(forEntry: entry),
                  !seen.contains(info.identity) else {
                continue
            }
            seen.insert(info.identity)
            result.append(info)
        }
        return result
    }

    private static func isExternalMouse(_ entry: io_registry_entry_t) -> Bool {
        let builtIn = IORegistryEntryCreateCFProperty(entry, kIOHIDBuiltInKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        if (builtIn as? NSNumber)?.boolValue == true { return false }
        // 触控板的滚动事件不经过 Mos 处理, 不列出
        if let name = stringProperty(entry, kIOHIDProductKey), name.localizedCaseInsensitiveContains("trackpad") {
            return false
        }
        // 任一 usage pair 为 Generic Desktop / Mouse 即视为鼠标 (接收器常有多个接口)
        let pairs = IORegistryEntryCreateCFProperty(entry, kIOHIDDeviceUsagePairsKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        if let pairs = pairs as? [[String: Any]] {
            return pairs.contains { pair in
                (pair[kIOHIDDeviceUsagePageKey] as? Int) == kHIDPage_GenericDesktop &&
                (pair[kIOHIDDeviceUsageKey] as? Int) == kHIDUsage_GD_Mouse
            }
        }
        return intProperty(entry, kIOHIDPrimaryUsagePageKey) == kHIDPage_GenericDesktop &&
            intProperty(entry, kIOHIDPrimaryUsageKey) == kHIDUsage_GD_Mouse
    }
}
