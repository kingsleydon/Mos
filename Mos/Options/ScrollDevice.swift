//
//  ScrollDevice.swift
//  Mos
//  例外设备对象
//

import Cocoa

class ScrollDevice: Codable, ScrollProfile {

    // 基础: 以 VendorID/ProductID 标识同型号设备
    let identity: String
    let vendorID: Int
    let productID: Int
    // IORegistry 中的产品名
    var name: String
    // 配置: 名称
    var displayName: String? = "" {
        didSet { Options.shared.markChanged(.device) }
    }
    // 配置: 已覆盖的设定项
    var overrides: Set<ScrollSetting> = [] {
        didSet { Options.shared.markChanged(.device) }
    }
    // 配置: 滚动
    var scroll = OPTIONS_SCROLL_DEFAULT() {
        didSet { Options.shared.markChanged(.device) }
    }
    var supportedSettings: Set<ScrollSetting> {
        return ScrollSetting.deviceSupported
    }

    init(vendorID: Int, productID: Int, name: String) {
        self.identity = ScrollDevice.identity(vendorID: vendorID, productID: productID)
        self.vendorID = vendorID
        self.productID = productID
        self.name = name
    }
    convenience init(info: PointingDeviceInfo) {
        self.init(vendorID: info.vendorID, productID: info.productID, name: info.name)
    }

    static func identity(vendorID: Int, productID: Int) -> String {
        return String(format: "%04x:%04x", vendorID, productID)
    }

    // Codable
    private enum CodingKeys: String, CodingKey {
        case vendorID, productID, name, displayName, overrides, scroll
    }
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vendorID = try container.decode(Int.self, forKey: .vendorID)
        productID = try container.decode(Int.self, forKey: .productID)
        identity = ScrollDevice.identity(vendorID: vendorID, productID: productID)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        let rawOverrides = try container.decodeIfPresent([String].self, forKey: .overrides) ?? []
        overrides = Set(rawOverrides.compactMap { ScrollSetting(rawValue: $0) })
        scroll = try container.decodeIfPresent(OPTIONS_SCROLL_DEFAULT.self, forKey: .scroll) ?? OPTIONS_SCROLL_DEFAULT()
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(vendorID, forKey: .vendorID)
        try container.encode(productID, forKey: .productID)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encode(overrides.map { $0.rawValue }.sorted(), forKey: .overrides)
        try container.encode(scroll, forKey: .scroll)
    }
}

extension ScrollDevice {
    func getName() -> String {
        if let customName = displayName, customName.count > 0 {
            return customName
        }
        if name.count > 0 {
            return name
        }
        return identity
    }
}
