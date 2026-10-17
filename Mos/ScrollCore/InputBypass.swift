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

/// 按下时被忽略的按键, 其重复与抬起也一并忽略 (按 类型/按键/来源设备 配对).
/// 每个事件 tap 各持一份, 互不消费对方的记录
class BypassedPressTracker {

    private struct Press: Hashable {
        let isMouse: Bool
        let code: Int64
        let sender: UInt64
    }
    private var presses = Set<Press>()

    private func press(for event: CGEvent, type: CGEventType) -> Press? {
        switch type {
        case .otherMouseDown, .otherMouseUp:
            // 无底层 HID 事件 (合成 / 远程) 时以来源进程区分, 避免不同来源共用一条记录
            let sender = PointingDeviceRegistry.shared.senderID(of: event)
                ?? (1 << 48 | UInt64(UInt32(truncatingIfNeeded: event.getIntegerValueField(.eventSourceUnixProcessID))))
            return Press(isMouse: true, code: event.getIntegerValueField(.mouseEventButtonNumber), sender: sender)
        case .keyDown, .keyUp:
            return Press(isMouse: false, code: event.getIntegerValueField(.keyboardEventKeycode), sender: 0)
        default:
            return nil
        }
    }

    /// 按下: 是否忽略. 自动重复只跟随已忽略的按下, 不会开始新的忽略 (按住时切换焦点, 已生效的绑定继续生效)
    func shouldBypassDown(_ event: CGEvent, type: CGEventType) -> Bool {
        guard let press = press(for: event, type: type) else { return false }
        if presses.contains(press) { return true }
        if type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return false }
        guard InputBypass.shared.shouldBypass(event, isPointingEvent: press.isMouse) else { return false }
        presses.insert(press)
        return true
    }

    /// 抬起: 仅当对应的按下被忽略时忽略
    func shouldBypassUp(_ event: CGEvent, type: CGEventType) -> Bool {
        guard let press = press(for: event, type: type) else { return false }
        return presses.remove(press) != nil
    }

    func reset() {
        presses.removeAll()
    }
}
