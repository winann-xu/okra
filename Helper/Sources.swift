import Foundation

/// 镜像源（主备降级，顺序即优先级）。数据均验证于 2026-09-17（任务书 §7/§11 D7）。
struct Source {
    let name: String
    let url: String
}

let defaultSources: [Source] = [
    Source(name: "hellogithub", url: "https://raw.hellogithub.com/hosts"),
    Source(name: "ittuann-jsdelivr", url: "https://cdn.jsdelivr.net/gh/ittuann/GitHub-IP-hosts@main/hosts"),
    Source(name: "github520", url: "https://raw.githubusercontent.com/521xueweihan/GitHub520/main/hosts"),
]

/// 测试覆盖：OKRA_SOURCES="url1,url2"（逗号分隔，覆盖默认源列表）。
func activeSources() -> [Source] {
    let env = ProcessInfo.processInfo.environment["OKRA_SOURCES"]
    guard let env, !env.isEmpty else { return defaultSources }
    return env.split(separator: ",").map {
        let u = URL(string: String($0))
        // https 源取 host；file:// 等无 host 的取文件名（便于区分与错误定位）
        let name = u?.host().map { $0.isEmpty ? nil : $0 } ?? u?.lastPathComponent
        return Source(name: name ?? "custom", url: String($0))
    }
}

/// 镜像源拉取 + 归一化 + 校验。
enum Sources {
    static let fetchTimeout: TimeInterval = 15

    static func fetch(_ source: Source) throws -> String {
        guard let u = URL(string: source.url) else { throw OkraError("源 URL 非法：\(source.url)") }
        if u.scheme == "file" {
            // file:// 仅配合 OKRA_SOURCES 测试覆盖使用（离线验收），非生产路径
            guard let data = try? Data(contentsOf: u) else {
                throw OkraError("源 \(source.name)（file）读取失败")
            }
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
                throw OkraError("源 \(source.name) 返回空内容")
            }
            return text
        }
        var req = URLRequest(url: u)
        req.timeoutInterval = fetchTimeout
        let (data, resp) = try fetchResponse(req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OkraError("源 \(source.name) 返回非 2xx 状态码")
        }
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            throw OkraError("源 \(source.name) 返回空内容")
        }
        return text
    }

    /// 同步等待 dataTask（daemon 场景不用 async/await，信号量足够）。
    private static func fetchResponse(_ req: URLRequest) throws -> (Data, URLResponse) {
        let sem = DispatchSemaphore(value: 0)
        var done: (Data, URLResponse?, Error?)?
        URLSession.shared.dataTask(with: req) { data, resp, error in
            done = (data ?? Data(), resp, error)
            sem.signal()
        }.resume()
        sem.wait()
        guard let (data, resp, error) = done else { throw OkraError("网络请求无响应") }
        if let error { throw error }
        guard let resp else { throw OkraError("网络请求无响应") }
        return (data, resp)
    }

    /// 逐行归一化：仅取合法 "IP + 域名" 行（源内原有 Start/End 标记与注释全部丢弃），按域名去重（保留首个 IP）。
    static func normalize(_ text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard isEntryLine(trimmed) else { continue }
            let host = trimmed.split(separator: " ").last.map(String.init) ?? ""
            if seen.insert(host).inserted { out.append(trimmed) }
        }
        return out
    }

    /// 合法条目行：单个 IPv4 + 一个或多个域名。
    static func isEntryLine(_ line: String) -> Bool {
        guard !line.hasPrefix("#") else { return false }
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2, let ip = parts.first else { return false }
        guard isValidIPv4(String(ip)) else { return false }
        for host in parts.dropFirst() {
            if !isValidHost(String(host)) { return false }
        }
        return true
    }

    static func isValidIPv4(_ ip: String) -> Bool {
        guard let r = ip.range(of: ipv4Regex, options: .regularExpression) else { return false }
        return r == ip.startIndex..<ip.endIndex
    }

    private static let ipv4Regex =
        "(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3}"

    private static func isValidHost(_ host: String) -> Bool {
        guard (1...253).contains(host.count), let r = host.range(of: hostRegex, options: .regularExpression) else {
            return false
        }
        return r == host.startIndex..<host.endIndex
    }

    private static let hostRegex =
        "[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*\\.?[A-Za-z]{2,}"

    /// 数据校验（铁律 5）：非空 + 行数剧变保护。
    static func validate(entries: [String], previousCount: Int?) throws {
        guard !entries.isEmpty else { throw OkraError("镜像数据异常：无有效 IP 行，拒绝写入") }
        if let prev = previousCount, prev > 0 {
            let delta = abs(entries.count - prev)
            if delta > prev / 2 {
                throw OkraError("镜像数据异常：行数剧变（\(prev) → \(entries.count)，超过 50% 阈值），拒绝写入")
            }
        }
    }

    /// 依次尝试各源，返回首个成功结果；全部失败时抛出聚合错误。
    static func fetchWithFallback() throws -> (source: Source, entries: [String]) {
        var errors: [String] = []
        for source in activeSources() {
            do {
                let text = try fetch(source)
                let entries = normalize(text)
                try validate(entries: entries, previousCount: nil)
                return (source, entries)
            } catch {
                errors.append("\(source.name): \(error)")
            }
        }
        throw OkraError("全部镜像源失败：" + errors.joined(separator: " | "))
    }
}
