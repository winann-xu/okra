import Foundation
import ServiceManagement

/// 登录项（任务书 FR1）：SMAppService（macOS 13+）把菜单栏 App 注册为登录项，
/// 用户登录即自启；卸载时经同入口移除。每次启动幂等注册。
enum LoginItem {
    static var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 注册登录项（幂等）。失败仅告警不阻塞主流程（如开发构建签名限制）。
    /// OKRA_DEBUG=1 时把注册前后状态打到 stderr（开发诊断用）。
    @discardableResult
    static func register() -> Bool {
        let debug = ProcessInfo.processInfo.environment["OKRA_DEBUG"] != nil
        if debug {
            FileHandle.standardError.write(
                Data("login-item status before register: raw=\(SMAppService.mainApp.status.rawValue)\n".utf8))
        }
        guard !isRegistered else { return true }
        do {
            try SMAppService.mainApp.register()
            if debug {
                FileHandle.standardError.write(
                    Data("login-item status after register: raw=\(SMAppService.mainApp.status.rawValue)\n".utf8))
            }
            return true
        } catch {
            FileHandle.standardError.write(
                Data("登录项注册失败：\(error.localizedDescription)\n".utf8))
            return false
        }
    }

    static func unregister() {
        guard isRegistered else { return }
        try? SMAppService.mainApp.unregister()
        let debug = ProcessInfo.processInfo.environment["OKRA_DEBUG"] != nil
        if debug {
            FileHandle.standardError.write(
                Data("login-item status after unregister: raw=\(SMAppService.mainApp.status.rawValue) (\(SMAppService.mainApp.status))\n".utf8))
        }
    }
}