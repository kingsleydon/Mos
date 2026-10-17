//
//  InputBypass.swift
//  Mos
//  停用 / 白名单: 判断 Mos 是否应完全忽略某个事件
//

import Cocoa

class InputBypass {

    // 单例
    static let shared = InputBypass()
    init() { NSLog("Module initialized: InputBypass") }

    // 事件目标进程缓存 (与 ScrollUtils 的缓存分开, 避免不同事件流互相抖动)
    private var cachedPID: pid_t = 0
    private var cachedRunningApplication: NSRunningApplication?

    /// 事件的目标应用的例外设置
    func targetApplication(of event: CGEvent) -> Application? {
        var pid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        if pid <= 1 {
            pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        }
        guard pid > 1 else { return nil }
        if pid != cachedPID {
            cachedPID = pid
            cachedRunningApplication = NSRunningApplication(processIdentifier: pid)
        }
        return ScrollUtils.shared.getTargetApplication(from: cachedRunningApplication)
    }

    /// Mos 是否应忽略该事件.
    /// - 应用规则作用于所有事件; 设备规则只作用于鼠标事件 (键盘不在设备列表中, 否则设备白名单会屏蔽键盘热键)
    func shouldBypass(_ event: CGEvent, isPointingEvent: Bool) -> Bool {
        let applicationAllowlist = Options.shared.application.allowlist
        let deviceAllowlist = isPointingEvent && Options.shared.device.allowlist
        let application = targetApplication(of: event)
        let device = isPointingEvent ? ScrollUtils.shared.getTargetDevice(from: event) : nil
        return !ScrollOptionsResolver.isActive(
            application: application,
            device: device,
            applicationAllowlist: applicationAllowlist,
            deviceAllowlist: deviceAllowlist
        )
    }
}
