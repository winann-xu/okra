import Foundation

/// 铁律核心：只管理 Okra 标记区块，区块外字节逐行原样保留；备份 + 原子写 + 写前校验。
/// 实现方式：按 \n 拆行操作，每行字节原样保留；写出前逐行比对区块外内容与原文件。
struct HostsFile {
    let path: String
    /// 每行不含末尾 \n 的原始字节
    private(set) var lines: [String]
    private(set) var endsWithNewline: Bool
    /// 初始化时的原样行（写前校验基准）
    private let originalLines: [String]

    init(path: String) throws {
        self.path = path
        let data: Data
        do { data = try Data(contentsOf: URL(fileURLWithPath: path)) }
        catch { throw OkraError("无法读取 hosts 文件：\(path)（\(error.localizedDescription)）") }
        let text = String(decoding: data, as: UTF8.self)
        endsWithNewline = text.hasSuffix("\n")
        var ls = text.components(separatedBy: "\n")
        if endsWithNewline { ls.removeLast() }
        lines = ls
        originalLines = ls
    }

    // MARK: - 区块定位

    /// 返回 Okra 区块的行范围 [start, end]（含两端标记行）；无完整区块返回 nil；标记损坏抛错。
    func blockRange() throws -> Range<Int>? {
        guard let r = lines.rangeOfOkraBlock() else {
            var hasAny = false
            for line in lines {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t == Paths.startMarker || t == Paths.endMarker { hasAny = true }
            }
            if hasAny {
                throw OkraError("hosts 文件中 Okra 标记损坏（只有单侧标记），拒绝操作以保护原内容")
            }
            return nil
        }
        return r
    }

    /// 区块内的条目行（不含标记）。
    func blockEntries() throws -> [String] {
        guard let r = try blockRange() else { return [] }
        return Array(lines[r].dropFirst().dropLast())
    }

    // MARK: - 备份（铁律 2）

    /// 写前完整备份（带时间戳，保留最近 10 份）。
    mutating func backup() throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: Paths.backupDir, withIntermediateDirectories: true)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let dest = Paths.backupDir + "/hosts-" + fmt.string(from: Date()) + ".bak"
        do {
            if fm.fileExists(atPath: dest) { try fm.removeItem(atPath: dest) }
            try fm.copyItem(atPath: path, toPath: dest)
            pruneBackups(keep: 10)
        } catch {
            throw OkraError("备份失败，放弃写入：\(error.localizedDescription)")
        }
    }

    private func pruneBackups(keep: Int) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: Paths.backupDir) else { return }
        let baks = items.filter { $0.hasPrefix("hosts-") && $0.hasSuffix(".bak") }.sorted()
        for old in baks.prefix(max(0, baks.count - keep)) {
            try? fm.removeItem(atPath: Paths.backupDir + "/" + old)
        }
    }

    // MARK: - 区块替换（铁律 3：替换而非追加，重复更新不产生重复条目）

    mutating func replaceBlock(entries: [String]) {
        var prefix: [String]
        var suffix: [String]
        if let r = try? blockRange() {
            prefix = Array(lines[..<r.lowerBound])
            suffix = Array(lines[r.upperBound...])
        } else {
            prefix = lines
            suffix = []
        }
        lines = prefix + [Paths.startMarker] + entries + [Paths.endMarker] + suffix
    }

    /// 移除 Okra 区块（一键还原，他人内容原样保留）；无区块返回 false（无改动）。
    mutating func removeBlock() -> Bool {
        guard let r = try? blockRange() else { return false }
        lines = Array(lines[..<r.lowerBound]) + Array(lines[r.upperBound...])
        return true
    }

    // MARK: - 写前校验 + 原子写（铁律 4、5）

    /// 铁律 4：候选内容的区块外行必须与原文件逐行一致且顺序不变。
    private func verifyCandidate(candidate: [String], candidateEndsNewline: Bool) throws {
        let origNonOkra = nonOkraLines(of: originalLines)
        let candNonOkra = nonOkraLines(of: candidate)
        guard candNonOkra == origNonOkra else {
            throw OkraError("写前校验失败：区块外内容与原文件不一致（\(origNonOkra.count) 行应原样保留），放弃写入")
        }
        guard candidateEndsNewline == endsWithNewline else {
            throw OkraError("写前校验失败：文件结尾换行状态变化，放弃写入")
        }
        guard !candidate.isEmpty else {
            throw OkraError("写前校验失败：候选文件为空，放弃写入")
        }
        // 本次写入了新区块 → 校验区块内容可解析（铁律 5）
        if candNonOkra.count != candidate.count {
            try HostsParseCheck(candidate: candidate).validate()
        }
    }

    private func nonOkraLines(of src: [String]) -> [String] {
        guard let r = src.rangeOfOkraBlock() else { return src }
        return Array(src[..<r.lowerBound]) + Array(src[r.upperBound...])
    }

    /// 原子写（铁律 4）：备份 → 写临时文件 → 回读校验 → rename 覆盖；任何一步失败则放弃，原文件不动。
    mutating func commit() throws {
        try backup()
        var text = lines.joined(separator: "\n")
        if endsWithNewline { text += "\n" }
        let tmp = path + ".okra-tmp-" + UUID().uuidString
        do {
            // 直接以内存行数组为校验基准；重新拆 text 在"文件无结尾换行"时会误删末行
            try verifyCandidate(candidate: lines, candidateEndsNewline: endsWithNewline)
            let url = URL(fileURLWithPath: tmp)
            try text.write(to: url, atomically: false, encoding: .utf8)
            let back = try Data(contentsOf: url)
            guard back == Data(text.utf8) else {
                throw OkraError("临时文件落盘校验失败（回读字节不一致），放弃写入")
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tmp)
            // 用 rename(2) 系统调用原子替换已存在的目标文件；
            // 本机 macOS 27 的 FileManager.moveItem 在目标已存在时报 EEXIST（实测），不可用。
            guard rename(tmp, path) == 0 else {
                throw OkraError("原子写失败（rename 失败：\(String(cString: strerror(errno)))），原文件未动")
            }
        } catch let e as OkraError {
            try? FileManager.default.removeItem(atPath: tmp)
            throw e
        } catch {
            try? FileManager.default.removeItem(atPath: tmp)
            throw OkraError("原子写失败，原文件未动：\(error.localizedDescription)")
        }
    }
}

extension Array where Element == String {
    /// Okra 区块行范围（含两端标记行）；无完整区块返回 nil。
    func rangeOfOkraBlock() -> Range<Int>? {
        var s: Int?
        var e: Int?
        for (i, line) in enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t == Paths.startMarker { s = i }
            else if t == Paths.endMarker { e = i }
        }
        guard let x = s, let y = e, x < y else { return nil }
        return x..<y + 1
    }
}

/// 候选 hosts 内容的可解析性校验（铁律 5）：
/// 若包含 Okra 区块，区块内每行必须为合法 "IP + 域名" 条目。
struct HostsParseCheck {
    let candidate: [String]

    func validate() throws {
        guard let r = candidate.rangeOfOkraBlock() else { return } // restore 场景：允许无区块
        let inner = Array(candidate[r].dropFirst().dropLast())
        guard !inner.isEmpty else { throw OkraError("校验失败：Okra 区块无有效条目，放弃写入") }
        for line in inner where !Sources.isEntryLine(line) {
            throw OkraError("校验失败：区块内存在非法条目行「\(line)」，放弃写入")
        }
    }
}
