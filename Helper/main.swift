import Foundation

// OkraHelper：root 级 launchd daemon（任务书 §7 组件 B）。
// 子命令：update（拉取→区块化更新→备份→刷 DNS→写状态）/ restore（还原）/
//         install / uninstall（launchd 与全部组件）/ status（打印状态文件）

// 顶层入口：Swift 编译器只把 main.swift 的顶层语句编译为程序入口，
// 仅声明 func main() 会生成空 _main 桩（进程静默退出 0，业务代码不执行）。
let args = Array(CommandLine.arguments.dropFirst())
let action = args.first ?? "update"
let opts = parseOptions(args)

do {
    switch action {
    case "update": try runUpdate()
    case "restore": try runRestore()
    case "install":
        try Install.install(userHome: opts["user-home"] ?? userHome(),
                            interval: opts["interval"].flatMap(Int.init))
    case "uninstall":
        try Install.uninstall(userHome: opts["user-home"] ?? userHome())
    case "status": printStatus()
    default:
        print("用法：OkraHelper [update|restore|install|uninstall|status] [--user-home PATH] [--interval N]")
    }
} catch let e as OkraError {
    try? StatusIO.writeUpdate(ok: false, error: e.description, source: nil, entries: nil)
    print("失败：\(e.description)")
    exit(1)
} catch {
    try? StatusIO.writeUpdate(ok: false, error: "\(error)", source: nil, entries: nil)
    print("失败：\(error)")
    exit(1)
}

func userHome() -> String {
    ProcessInfo.processInfo.environment["OKRA_USER_HOME"] ?? NSHomeDirectory()
}

/// 解析 --key value 选项。
func parseOptions(_ args: [String]) -> [String: String] {
    var opts: [String: String] = [:]
    var i = 1
    while i < args.count {
        if args[i].hasPrefix("--") {
            let key = String(args[i].dropFirst(2))
            opts[key] = (i + 1 < args.count && !args[i + 1].hasPrefix("--")) ? args[i + 1] : ""
            i += 2
        } else {
            i += 1
        }
    }
    return opts
}

// MARK: - update

func runUpdate() throws {
    print("秋葵更新开始…")
    let result: (source: Source, entries: [String])
    do {
        result = try Sources.fetchWithFallback()
    } catch let e as OkraError {
        // 拉取失败：保留上一次可用配置，状态文件标记 error（任务书 FR2）
        try StatusIO.writeUpdate(ok: false, error: e.description, source: nil, entries: nil)
        throw e
    }
    var hosts = try HostsFile(path: Paths.hostsPath)
    let previous = try hosts.blockEntries().count
    // 三源条目数天然不同（47/169/40），源切换时不做 50% 剧变比对（否则主源停摆后备源永远被拒）；
    // 同源连续更新才比对剧变（防镜像上游被篡改/数据损坏，铁律 5）。
    let previousSource = StatusIO.read().source
    try Sources.validate(entries: result.entries,
                         previousCount: previousSource == result.source.name ? previous : nil)
    hosts.replaceBlock(entries: result.entries)
    try hosts.commit()
    Dns.flush()
    try StatusIO.writeUpdate(ok: true, error: nil,
                             source: result.source.name, entries: result.entries.count)
    print("更新完成：源 \(result.source.name)，\(result.entries.count) 条目标记已写入（原区块 \(previous) 条）")
    print("状态文件：\(Paths.statusFile)")
}

// MARK: - restore

func runRestore() throws {
    var hosts = try HostsFile(path: Paths.hostsPath)
    guard hosts.removeBlock() else {
        print("hosts 中无 Okra 区块，无需还原")
        return
    }
    try hosts.commit()
    Dns.flush()
    try StatusIO.writeUpdate(ok: true, error: nil, source: nil, entries: 0)
    print("已还原：Okra 区块移除，其余 hosts 内容原样保留")
}

// MARK: - status

func printStatus() {
    let s = StatusIO.read()
    if s.updateOk == nil && s.lastProbe == nil {
        print("（尚无状态数据）")
        return
    }
    let okText = s.updateOk == true ? "成功" : (s.updateOk == false ? "失败" : "—")
    print("最近更新：\(s.lastUpdate ?? "—")（\(okText)\(s.source.map { "，源 \($0)" } ?? "")\(s.entries.map { "，\($0) 条" } ?? "")）")
    if let err = s.updateError { print("错误：\(err)") }
    if let p = s.lastProbe { print("最近探测：\(p)（总体：\(s.overall ?? "—")）") }
}
