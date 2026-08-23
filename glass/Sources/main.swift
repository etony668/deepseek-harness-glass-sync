// DeepSeek Harness — 原生 SwiftUI 液态玻璃壳
//
// 架构与 Electron 壳完全一致，但玻璃效果使用苹果公开 API：
//   - 窗口级玻璃：.containerBackground(.glass, for: .window)（macOS 26+，
//     苹果自家应用同款，含边缘折射/散射）
//   - 透明 WKWebView 加载 dsh 前端，注入 GLASS_CSS 把设计令牌改为半透明
//   - 内置官方源码构建的 Node + pnpm + dsh 运行时，
//     spawn `dsh web --port 0`，解析 stdout 拿到端口后加载
//   - DSH_HOME 默认 ~/.dsh，与 CLI 共享凭据/会话/配置/插件 Profile
//
// 编译：swiftc -O -parse-as-library -target arm64-apple-macosx26.0 Sources/main.swift

import SwiftUI
import WebKit
import AppKit

// MARK: - 玻璃 CSS（与 Electron 版同款，注入到 dsh 前端）

let GLASS_CSS = """
html, body, #root { background: transparent !important; }
/* 顶部边条加高：内容整体下移 26pt，让标题/三点菜单与窗口顶边保持距离 */
#root { padding-top: 26px !important; box-sizing: border-box !important; }
/* 边条与主体同色：给 26pt 留白带补上与主体一致的衬底，消除色差 */
body[data-ds-dark-theme] #root::before {
  content: "";
  position: fixed;
  top: 0; left: 0; right: 0;
  height: 26px;
  background: rgba(13, 14, 18, 0.03);
  pointer-events: none;
}
body:not([data-ds-dark-theme]) #root::before {
  content: "";
  position: fixed;
  top: 0; left: 0; right: 0;
  height: 26px;
  background: rgba(255, 255, 255, 0.01);
  pointer-events: none;
}
html { color-scheme: light !important; }
html, body { -webkit-font-smoothing: antialiased !important; }
/* 极淡衬底：给文字一个近实底，阻断玻璃背后颜色渗进字形（4% 几乎不可见） */
body::before {
  content: "";
  position: fixed;
  inset: 0;
  background: rgba(255, 255, 255, 0.005);
  z-index: -1;
  pointer-events: none;
}
body[data-ds-dark-theme] {
  /*
   深色主题不能把主背景做成近乎透明。macOS 的玻璃会透出桌面壁纸；
   当壁纸偏亮时，3% 深色填充会变成亮底白字，整页失去可读性。
   保留少量透光，但给所有内容区稳定的深色衬底。
   */
  background: rgba(18, 19, 23, 0.80) !important;
  --dsw-alias-bg-base: rgba(18, 19, 23, 0.80) !important;
  --dsw-alias-bg-layer-1: rgba(28, 29, 34, 0.82) !important;
  --dsw-alias-bg-layer-2: rgba(36, 37, 43, 0.86) !important;
  --dsw-alias-bg-layer-3: rgba(44, 45, 52, 0.90) !important;
  --dsw-alias-bg-module-platform: rgba(13, 14, 18, 0.82) !important;
  --dsw-alias-bg-overlay: rgba(44, 45, 52, 0.70) !important;
  --dsw-alias-bg-multi-select: rgba(33, 34, 40, 0.82) !important;
  --dsw-alias-toast-bg: rgba(60, 60, 61, 0.92) !important;
  --dsw-alias-tooltip-bg: rgba(33, 33, 35, 0.94) !important;
  --dsw-specific-sidebar-fill: rgba(22, 23, 28, 0.76) !important;
  --dsw-specific-menu: rgba(38, 39, 46, 0.82) !important;
  --dsw-specific-selector: rgba(34, 35, 41, 0.78) !important;
  --dsw-specific-tip: rgba(36, 37, 43, 0.76) !important;
  --dsw-specific-input-major: rgba(28, 29, 34, 0.76) !important;
  --dsw-specific-login-input: rgba(30, 31, 37, 0.80) !important;
  --dsw-specific-bubble: rgba(30, 31, 36, 0.72) !important;
  --dsw-specific-bubble-highlight: rgba(30, 31, 36, 0.80) !important;
  --dsw-hovercard-bg: rgba(38, 39, 46, 0.86) !important;
  --dsw-alias-markdown-code-block: rgba(26, 27, 32, 0.78) !important;
  --dsw-alias-markdown-code-block-banner: rgba(30, 31, 36, 0.82) !important;
  --dsw-alias-label-primary: rgb(240, 242, 245) !important;
  --dsw-alias-label-primary-dimmed: rgb(225, 229, 238) !important;
  --dsw-alias-label-primary-bluish: rgb(147, 197, 253) !important;
  --dsw-alias-label-secondary: rgb(207, 211, 214) !important;
  --dsw-alias-label-tertiary: rgb(173, 178, 184) !important;
  --dsw-alias-label-caption: rgb(151, 157, 166) !important;
  --dsw-alias-label-dimmed: rgb(127, 130, 135) !important;
  --dsw-alias-markdown-citation: rgb(53, 54, 56) !important;
  --dsw-alias-markdown-tag: rgb(44, 44, 46) !important;
  --dsw-alias-markdown-inline-code: rgb(44, 44, 46) !important;
  --dsw-alias-markdown-code-segment-unselected: rgb(27, 27, 28) !important;
  --dsw-alias-markdown-placeholder: rgb(101, 103, 107) !important;
}
body:not([data-ds-dark-theme]) {
  color-scheme: light !important;
  --dsw-alias-bg-base: rgba(255, 255, 255, 0.78) !important;
  --dsw-alias-bg-layer-1: rgba(255, 255, 255, 0.84) !important;
  --dsw-alias-bg-layer-2: rgba(255, 255, 255, 0.92) !important;
  --dsw-alias-bg-layer-3: rgba(255, 255, 255, 0.96) !important;
  --dsw-alias-bg-module-platform: rgba(255, 255, 255, 0.80) !important;
  --dsw-alias-bg-overlay: rgba(255, 255, 255, 0.92) !important;
  --dsw-alias-toast-bg: rgba(60, 60, 61, 0.92) !important;
  --dsw-alias-tooltip-bg: rgba(33, 33, 35, 0.94) !important;
  --dsw-specific-sidebar-fill: rgba(255, 255, 255, 0.76) !important;
  --dsw-specific-menu: rgba(255, 255, 255, 0.88) !important;
  --dsw-specific-selector: rgba(255, 255, 255, 0.84) !important;
  --dsw-specific-tip: rgba(255, 255, 255, 0.80) !important;
  --dsw-specific-input-major: rgba(255, 255, 255, 0.84) !important;
  --dsw-specific-login-input: rgba(255, 255, 255, 0.88) !important;
  --dsw-specific-bubble: rgba(255, 255, 255, 0.78) !important;
  --dsw-specific-bubble-highlight: rgba(255, 255, 255, 0.84) !important;
  --dsw-hovercard-bg: rgba(255, 255, 255, 0.94) !important;
  --dsw-alias-markdown-code-block: rgba(250, 250, 250, 0.84) !important;
  --dsw-alias-markdown-code-block-banner: rgba(255, 255, 255, 0.88) !important;
  /* Harness 的浅色主题必须保持深色前景。不要把壁纸采样得到的
     --glass-txt-*（深色壁纸时可能是白色）带入浅色主题，否则透明玻璃
     会让整页文字在浅色背景上几乎消失。 */
  --dsw-alias-label-primary: rgb(15, 17, 21) !important;
  --dsw-alias-label-secondary: rgb(53, 54, 56) !important;
  --dsw-alias-label-tertiary: rgb(84, 85, 87) !important;
  --dsw-alias-label-caption: rgb(97, 102, 107) !important;
  --dsw-alias-label-dimmed: rgb(129, 133, 140) !important;
  --dsw-alias-markdown-placeholder: rgb(162, 164, 166) !important;
  --dsw-alias-label-primary-dimmed: rgb(53, 54, 56) !important;
  --dsw-alias-label-primary-bluish: rgb(14, 48, 116) !important;
  --dsw-alias-markdown-citation: rgb(235, 238, 242) !important;
  --dsw-alias-markdown-tag: rgb(241, 243, 245) !important;
  --dsw-alias-markdown-inline-code: rgb(235, 238, 242) !important;
  --dsw-alias-markdown-code-segment-unselected: rgb(241, 243, 245) !important;
  --dsw-alias-state-warn-label: rgb(180, 120, 0) !important;
}
"""

// MARK: - 官方运行时同步状态（原生同步面板与菜单共用）

struct OfficialRuntimeSyncProgress: Sendable {
    let phase: String
    let fraction: Double
    let title: String
    let detail: String

    static func checkingLatest() -> Self {
        Self(
            phase: "check",
            fraction: 0.02,
            title: "正在检查官方更新",
            detail: "正在读取 DeepSeek Harness 官方最新提交"
        )
    }
}

// MARK: - 后端控制器（实例复用 + spawn 内置 dsh + 崩溃自动恢复 + 生命周期）

final class BackendController: NSObject, ObservableObject {
    static let shared = BackendController()
    static let didBecomeReady = Notification.Name("BackendController.didBecomeReady")

    @Published var url: URL?
    @Published var errorText: String?

    private var process: Process?
    private var captured = ""
    private var restartCount = 0
    private var suppressNextExit = false
    private var isQuitting = false
    /// 该实例是否由我们拉起（复用外部 dsh 时不拥有、退出时不能杀）。
    private(set) var ownsBackend = true

    var homePath: String {
        if let env = ProcessInfo.processInfo.environment["DSH_HOME"], !env.isEmpty {
            return env
        }
        return (NSHomeDirectory() as NSString).appendingPathComponent(".dsh")
    }

    var logPath: String {
        let dir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return (dir as NSString).appendingPathComponent("DeepSeek Harness Glass.log")
    }

    private var resourcesURL: URL {
        Bundle.main.resourceURL!
    }

    private var runtimeRootURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return appSupport
            .appendingPathComponent("DeepSeek Harness Glass", isDirectory: true)
            .appendingPathComponent("runtime", isDirectory: true)
    }

    private var activeBackendURL: URL {
        let current = runtimeRootURL
            .appendingPathComponent("current", isDirectory: true)
            .appendingPathComponent("lib", isDirectory: true)
            .appendingPathComponent("bin.js")
        return FileManager.default.fileExists(atPath: current.path)
            ? current
            : resourcesURL
                .appendingPathComponent("backend", isDirectory: true)
                .appendingPathComponent("lib", isDirectory: true)
                .appendingPathComponent("bin.js")
    }

    private var nodeURL: URL {
        resourcesURL.appendingPathComponent("node/node")
    }

    private var dshBinURL: URL {
        activeBackendURL
    }

    private var bundledBinPath: String {
        resourcesURL.appendingPathComponent("bin").path
    }

    private var bundledRuntimeCommit: String {
        guard let value = try? String(
            contentsOf: resourcesURL.appendingPathComponent("bundled-runtime-commit"),
            encoding: .utf8
        ) else { return "unknown" }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var officialRuntimeSyncLogPath: String {
        runtimeRootURL.appendingPathComponent("latest-sync.log").path
    }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillTerminate),
            name: NSApplication.willTerminateNotification, object: nil
        )
    }

    @objc private func appWillTerminate() {
        shutdown()
    }

    /// 终止我们自己的后端子进程（复用外部实例时不杀它）。
    func shutdown() {
        isQuitting = true
        if ownsBackend, let p = process, p.isRunning {
            p.terminate()
        }
    }

    private func appendLog(_ text: String) {
        if let h = FileHandle(forWritingAtPath: logPath) {
            h.seekToEndOfFile()
            h.write(Data(text.utf8))
            try? h.close()
        } else {
            try? Data(text.utf8).write(to: URL(fileURLWithPath: logPath))
        }
    }

    /// 启动后端。先探测 127.0.0.1:3080 上是否已有 dsh 实例：
    /// 有则直接挂接（不重复起实例），没有才拉起内置引擎。
    func start(autoRestart: Bool = false) {
        guard process == nil else { return }
        if !autoRestart { restartCount = 0 }
        errorText = nil
        captured = ""

        checkForExistingInstance { [weak self] found in
            guard let self else { return }
            if found {
                self.ownsBackend = false
                self.url = URL(string: "http://127.0.0.1:3080/")
                self.appendLog("[backend] 检测到 127.0.0.1:3080 已有 dsh 实例，直接挂接\n")
            } else {
                self.spawnBackend()
            }
        }
    }

    /// 手动重启后端（菜单/托盘入口）。
    func restart() {
        url = nil
        captured = ""
        restartCount = 0
        if ownsBackend, let p = process, p.isRunning {
            suppressNextExit = true
            p.terminate()
        }
        process = nil
        start()
    }

    /// 探测 3080 端口上是否为 dsh（响应体含 __DSH_BOOT__ 才算）。
    private func checkForExistingInstance(completion: @escaping (Bool) -> Void) {
        guard let probe = URL(string: "http://127.0.0.1:3080/") else {
            completion(false); return
        }
        var request = URLRequest(url: probe)
        request.timeoutInterval = 1.5
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let ok = status == 200 && body.contains("__DSH_BOOT__")
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }

    private func spawnBackend() {
        let node = nodeURL
        let bin = dshBinURL

        guard FileManager.default.fileExists(atPath: node.path) else {
            errorText = "缺少内置 Node 运行时：\(node.path)"
            return
        }
        guard FileManager.default.fileExists(atPath: bin.path) else {
            errorText = "缺少内置 dsh 后端：\(bin.path)"
            return
        }
        try? FileManager.default.createDirectory(atPath: homePath, withIntermediateDirectories: true)

        let proc = Process()
        proc.executableURL = node
        proc.arguments = ["--expose-internals", bin.path, "web", "--no-open", "--port", "0"]
        var env = ProcessInfo.processInfo.environment
        env["DSH_HOME"] = homePath
        env["PATH"] = bundledBinPath + ":" + (env["PATH"] ?? "")
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                self?.handleOutput(text)
            }
        }

        proc.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                guard let self else { return }
                self.process = nil
                if self.isQuitting { return }
                if self.suppressNextExit { self.suppressNextExit = false; return }
                if self.restartCount < 1 {
                    self.restartCount += 1
                    self.url = nil
                    self.appendLog("[backend] 后端退出（code=\(p.terminationStatus)），0.6 秒后自动重启（1/1）\n")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                        self?.start(autoRestart: true)
                    }
                } else {
                    self.url = nil
                    self.errorText = "后端连续两次退出（code=\(p.terminationStatus)）。"
                        + "请点「重新启动」，或运行 glass/repair-backend.sh 重装后端。日志：\(self.logPath)"
                }
            }
        }

        ownsBackend = true
        do {
            try proc.run()
            process = proc
        } catch {
            errorText = "无法启动后端：\(error.localizedDescription)"
        }
    }

    private func handleOutput(_ text: String) {
        appendLog(text)
        captured += text
        if url == nil,
           let range = captured.range(
               of: #"dsh web:\s+(https?://127\.0\.0\.1(?::\d+)?/?\S*)"#,
               options: .regularExpression
           ) {
            let match = String(captured[range])
            if let u = match.split(separator: " ").last.map(String.init),
               let parsed = URL(string: u) {
                url = parsed
                NotificationCenter.default.post(name: Self.didBecomeReady, object: self)
            }
        }
    }

    /// 使用 App 内置 Node 与 pnpm 调用官方 `dsh plugin`。Profile 目录和
    /// Bundle 解析完全由官方运行时负责，Swift 只提供触发入口。
    func runPluginCommand(_ arguments: [String], completion: @escaping (Bool, String) -> Void) {
        let node = nodeURL
        let bin = dshBinURL
        guard FileManager.default.fileExists(atPath: node.path),
              FileManager.default.fileExists(atPath: bin.path) else {
            completion(false, "App 内置的官方 dsh 运行时不完整，请重新安装。")
            return
        }

        let proc = Process()
        proc.executableURL = node
        proc.arguments = ["--expose-internals", bin.path, "plugin", "--profile", "web"] + arguments
        var env = ProcessInfo.processInfo.environment
        env["DSH_HOME"] = homePath
        env["PATH"] = bundledBinPath + ":" + (env["PATH"] ?? "")
        proc.environment = env

        let pipe = Pipe()
        let output = ProcessOutputBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            output.append(data)
        }
        proc.standardOutput = pipe
        proc.standardError = pipe
        proc.terminationHandler = { process in
            let remainder = pipe.fileHandleForReading.readDataToEndOfFile()
            output.append(remainder)
            let text = output.text
            DispatchQueue.main.async {
                if process.terminationStatus == 0 {
                    completion(true, text)
                } else {
                    completion(false, text.isEmpty
                        ? "官方 dsh plugin 退出（code=\(process.terminationStatus)）。"
                        : text)
                }
            }
        }
        do {
            try proc.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            completion(false, "无法启动官方 dsh plugin：\(error.localizedDescription)")
        }
    }

    /// 查询官方 GitHub master 当前提交，并在用户级 Application Support 中
    /// 构建/激活版本化 runtime。App 包和 DSH_HOME 都不会被改写。
    func syncOfficialRuntime(
        progress: @escaping (OfficialRuntimeSyncProgress) -> Void,
        completion: @escaping (Bool, String) -> Void
    ) {
        progress(.checkingLatest())
        fetchLatestOfficialCommit { [weak self] commit, error in
            guard let self else { return }
            if let error {
                completion(false, "无法读取官方 Harness 更新：\(error)")
                return
            }

            guard let commit else {
                completion(false, "官方更新响应缺少有效 commit。")
                return
            }

            let current = self.currentRuntimeCommit()
            if current == commit {
                let state = OfficialRuntimeSyncProgress(
                    phase: "complete",
                    fraction: 1,
                    title: "官方 Harness 已是最新",
                    detail: "当前版本为 \(String(commit.prefix(12)))"
                )
                progress(state)
                completion(true, state.detail)
                return
            }
            self.runOfficialSyncProcess(
                commit: commit,
                progress: progress,
                completion: completion
            )
        }
    }

    private func currentRuntimeCommit() -> String? {
        let metadata = runtimeRootURL
            .appendingPathComponent("current", isDirectory: true)
            .appendingPathComponent(".deepseek-harness-glass-runtime.json")
        if let data = try? Data(contentsOf: metadata),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let commit = object["commit"] as? String {
            return commit
        }
        return bundledRuntimeCommit == "unknown" ? nil : bundledRuntimeCommit
    }

    private func fetchLatestOfficialCommit(
        completion: @escaping (_ commit: String?, _ error: String?) -> Void
    ) {
        guard let url = URL(string:
            "https://api.github.com/repos/deepseek-ai/deepseek-harness/commits/master"
        ) else {
            completion(nil, "官方更新地址无效。")
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("DeepSeek-Harness-Glass", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                DispatchQueue.main.async { completion(nil, error.localizedDescription) }
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200, let data else {
                DispatchQueue.main.async {
                    completion(nil, "官方 GitHub 返回 HTTP \(status)。")
                }
                return
            }
            guard
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let commit = object["sha"] as? String,
                commit.count == 40,
                commit.allSatisfy({ $0.isHexDigit })
            else {
                DispatchQueue.main.async { completion(nil, "官方更新响应缺少有效 commit。") }
                return
            }
            DispatchQueue.main.async { completion(commit, nil) }
        }.resume()
    }

    private func runOfficialSyncProcess(
        commit: String,
        progress: @escaping (OfficialRuntimeSyncProgress) -> Void,
        completion: @escaping (Bool, String) -> Void
    ) {
        let script = resourcesURL.appendingPathComponent("bin/sync-official-runtime")
        guard FileManager.default.fileExists(atPath: script.path) else {
            completion(false, "App 缺少官方同步工具，请重新安装。")
            return
        }
        try? FileManager.default.createDirectory(
            at: runtimeRootURL,
            withIntermediateDirectories: true
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, runtimeRootURL.path, commit]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = bundledBinPath + ":" + (environment["PATH"] ?? "")
        process.environment = environment
        let pipe = Pipe()
        let output = ProcessOutputBuffer()
        let lines = ProcessLineBuffer()
        let latestProgress = SyncProgressStore()
        let handleLine: (String) -> Void = { [weak self] line in
            guard let self else { return }
            if let state = Self.parseOfficialSyncProgress(line) {
                latestProgress.replace(state)
                DispatchQueue.main.async { progress(state) }
            } else if !line.isEmpty {
                self.appendLog("[sync] \(line)\n")
            }
        }
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            output.append(data)
            for line in lines.append(data) {
                handleLine(line)
            }
        }
        process.standardOutput = pipe
        process.standardError = pipe
        process.terminationHandler = { [weak self] process in
            // 停止 readability 回调后再读取 EOF 尾部，避免两个读取者竞争
            // 同一段最后输出，造成进度事件重复或缺失。
            pipe.fileHandleForReading.readabilityHandler = nil
            let remainder = pipe.fileHandleForReading.readDataToEndOfFile()
            output.append(remainder)
            for line in lines.append(remainder) + lines.finish() {
                handleLine(line)
            }
            let raw = output.text
            let state = latestProgress.value
            DispatchQueue.main.async {
                guard let self else { return }
                if process.terminationStatus == 0 {
                    completion(true, state?.detail ?? "官方 Harness 已更新。")
                    return
                }
                let detail = state?.detail
                    ?? (raw.isEmpty
                        ? "官方同步进程退出（code=\(process.terminationStatus)）。"
                        : raw)
                completion(
                    false,
                    "\(detail)\n\n诊断日志：\(self.officialRuntimeSyncLogPath)"
                )
            }
        }
        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            completion(false, "无法启动官方同步：\(error.localizedDescription)")
        }
    }

    private static func parseOfficialSyncProgress(_ line: String) -> OfficialRuntimeSyncProgress? {
        let prefix = "@@DSH_SYNC@@"
        guard line.hasPrefix(prefix),
              let data = String(line.dropFirst(prefix.count)).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let phase = object["phase"] as? String,
              let fraction = object["fraction"] as? NSNumber,
              let title = object["title"] as? String,
              let detail = object["detail"] as? String
        else { return nil }
        return OfficialRuntimeSyncProgress(
            phase: phase,
            fraction: min(max(fraction.doubleValue, 0), 1),
            title: title,
            detail: detail
        )
    }
}

/// `Process` 输出会在后台队列抵达；用锁封装，避免插件安装日志多时堵塞管道，
/// 也避免 Swift 并发检查把可变捕获视为数据竞争。
final class ProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ more: Data) {
        lock.lock()
        data.append(more)
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 从共享 stdout/stderr 管道中拆出完整文本行。同步脚本只在 stdout 输出结构化
/// 进度事件，stderr 保留为诊断日志，不会污染原生同步面板。
final class ProcessLineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var remainder = ""

    func append(_ data: Data) -> [String] {
        let text = String(decoding: data, as: UTF8.self)
        lock.lock()
        remainder += text
        let parts = remainder.split(separator: "\n", omittingEmptySubsequences: false)
        if remainder.hasSuffix("\n") {
            remainder = ""
            lock.unlock()
            return parts.dropLast().map(String.init)
        }
        remainder = parts.last.map(String.init) ?? ""
        lock.unlock()
        return parts.dropLast().map(String.init)
    }

    func finish() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard !remainder.isEmpty else { return [] }
        defer { remainder = "" }
        return [remainder]
    }
}

/// 同步进度同时由 Pipe readability 和 termination handler 读取；用锁保存最后
/// 一个结构化事件，确保最终结果与原生同步面板一致。
final class SyncProgressStore: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: OfficialRuntimeSyncProgress?

    func replace(_ value: OfficialRuntimeSyncProgress) {
        lock.lock()
        latest = value
        lock.unlock()
    }

    var value: OfficialRuntimeSyncProgress? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }
}

/// Harness 网页自己的主题选择（浅色/深色/跟随系统）会与 macOS 系统外观不同。
/// 原生同步窗口不读取或修改官方 Settings，只订阅 WebView 上报的最终主题状态。
final class HarnessTheme {
    static let shared = HarnessTheme()
    static let didChange = Notification.Name("HarnessTheme.didChange")

    private(set) var isDark: Bool

    private init() {
        isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    func setDark(_ value: Bool) {
        guard isDark != value else { return }
        isDark = value
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

/// 原生同步面板：不进入官方 Harness Web DOM，因此不会影响 Settings 的布局。
final class OfficialRuntimeSyncPanelController: NSWindowController {
    private let titleLabel: NSTextField
    private let detailLabel: NSTextField
    private let progress: NSProgressIndicator
    private var themeObserver: NSObjectProtocol?
    private weak var parentWindow: NSWindow?

    init(parentWindow: NSWindow) {
        self.parentWindow = parentWindow
        titleLabel = NSTextField(labelWithString: "正在检查官方更新")
        detailLabel = NSTextField(labelWithString: "")
        progress = NSProgressIndicator()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 150),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = "同步官方 Harness"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        // 作为主窗口的 child window 显示。独立 floating panel 在 macOS
        // 全屏空间中可能让主窗口退出/缩回普通内容尺寸。
        panel.collectionBehavior.insert(.fullScreenAuxiliary)

        let stack = NSStackView(views: [titleLabel, detailLabel, progress])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = NSView()
        panel.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor),
            progress.widthAnchor.constraint(equalToConstant: 472),
        ])

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2
        detailLabel.lineBreakMode = .byTruncatingTail
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.doubleValue = 0
        progress.controlSize = .regular

        super.init(window: panel)
        themeObserver = NotificationCenter.default.addObserver(
            forName: HarnessTheme.didChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyHarnessAppearance()
        }
        applyHarnessAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    deinit {
        if let themeObserver {
            NotificationCenter.default.removeObserver(themeObserver)
        }
    }

    func update(_ state: OfficialRuntimeSyncProgress) {
        titleLabel.stringValue = "\(state.title)  \(Int((state.fraction * 100).rounded()))%"
        detailLabel.stringValue = state.detail
        progress.doubleValue = state.fraction
    }

    func show() {
        guard let window else { return }
        applyHarnessAppearance()
        if let parentWindow {
            let parentRect = parentWindow.convertToScreen(parentWindow.contentLayoutRect)
            window.setFrameOrigin(NSPoint(
                x: parentRect.midX - window.frame.width / 2,
                y: parentRect.midY - window.frame.height / 2
            ))
            if window.parent !== parentWindow {
                parentWindow.addChildWindow(window, ordered: .above)
            }
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    func closePanel() {
        if let parent = window?.parent, let window {
            parent.removeChildWindow(window)
        }
        window?.orderOut(nil)
    }

    private func applyHarnessAppearance() {
        window?.appearance = NSAppearance(
            named: HarnessTheme.shared.isDark ? .darkAqua : .aqua
        )
    }
}

// MARK: - 动态反色文字（苹果式自适应：按窗口背后壁纸亮度取反色）

final class DynamicContrast {
    static let shared = DynamicContrast()
    static let didChange = Notification.Name("DynamicContrast.didChange")

    /// 0 = 背景很暗，1 = 背景很亮
    private(set) var luminance: Double = 0.5

    private struct Endpoint { let r: Double; let g: Double; let b: Double }
    /// 背景暗 -> 文字亮（反色）
    private let darkBackdrop: [String: Endpoint] = [
        "primary": Endpoint(r: 240, g: 242, b: 245),
        "secondary": Endpoint(r: 225, g: 229, b: 238),
        "tertiary": Endpoint(r: 207, g: 211, b: 214),
        "caption": Endpoint(r: 173, g: 178, b: 184),
        "dimmed": Endpoint(r: 151, g: 157, b: 166),
        "placeholder": Endpoint(r: 127, g: 130, b: 135),
    ]
    /// 背景亮 -> 文字深
    private let brightBackdrop: [String: Endpoint] = [
        "primary": Endpoint(r: 15, g: 17, b: 21),
        "secondary": Endpoint(r: 53, g: 54, b: 56),
        "tertiary": Endpoint(r: 84, g: 85, b: 87),
        "caption": Endpoint(r: 97, g: 102, b: 107),
        "dimmed": Endpoint(r: 129, g: 133, b: 140),
        "placeholder": Endpoint(r: 162, g: 164, b: 166),
    ]

    private(set) var colors: [String: String] = [:]

    func setLuminance(_ l: Double) {
        let clamped = min(max(l, 0), 1)
        // 苹果式阈值翻转：亮背景 -> 深字，暗背景 -> 浅字（不做中间灰渐变）。
        // 带 0.45/0.55 迟滞，避免在阈值附近来回闪。
        let target: Double
        if luminance >= 0.5 {
            target = clamped < 0.45 ? 0.0 : 1.0
        } else {
            target = clamped > 0.55 ? 1.0 : 0.0
        }
        guard abs(target - luminance) > 0.01 || colors.isEmpty else { return }
        luminance = target
        colors = Self.interpolate(from: darkBackdrop, to: brightBackdrop, t: target)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    private static func interpolate(
        from: [String: Endpoint], to: [String: Endpoint], t: Double
    ) -> [String: String] {
        var out: [String: String] = [:]
        for (key, a) in from {
            guard let b = to[key] else { continue }
            let r = Int((a.r + (b.r - a.r) * t).rounded())
            let g = Int((a.g + (b.g - a.g) * t).rounded())
            let bl = Int((a.b + (b.b - a.b) * t).rounded())
            out[key] = "rgb(\(r), \(g), \(bl))"
        }
        return out
    }

    /// 生成注入 WKWebView 的 JS：把当前颜色写进 --glass-txt-* CSS 变量。
    var jsPayload: String {
        var lines: [String] = []
        for (key, color) in colors {
            lines.append("r.style.setProperty('--glass-txt-\(key)','\(color)')")
        }
        return "(()=>{var r=document.documentElement;\(lines.joined(separator: ";"));})()"
    }
}

// MARK: - WKWebView（透明 + CSS 注入）

final class GlassWebViewController: NSViewController, WKNavigationDelegate, WKDownloadDelegate,
    WKScriptMessageHandler {
    private let webView: WKWebView
    private var loaded = false
    private var contrastObserver: NSObjectProtocol?

    init(url: URL) {
        let config = WKWebViewConfiguration()
        let css = GLASS_CSS
        let script = WKUserScript(
            source: """
            (function () {
              if (!document.getElementById('dsh-glass-style')) {
                var s = document.createElement('style')
                s.id = 'dsh-glass-style'
                s.textContent = `\(css)`
                document.documentElement.appendChild(s)
              }
              // 不要对网页中的所有容器强行加 backdrop-filter。filter 会建立新的
              // containing block，使官方 Settings 的 fixed overlay 错误地相对侧栏
              // 定位，造成设置页宽度塌缩、文字换行。玻璃由原生窗口材质负责。
              // API Key 首次引导的两个操作按钮原本按文案自然宽度渲染，
              // 因而“稍后配置”和“保存并继续”会显得大小不同。不要依赖
              // CSS Module 的编译类名：只识别带必填密码框的引导 dialog，
              // 找到其唯一的双按钮操作行后，将两者统一为较大的实际尺寸。
              // 这样中英文以及未来上游调整的文案都不会重新引入此问题。
              function dshEqualizeCredentialOnboardingActions() {
                var dialogs = document.querySelectorAll('[role="dialog"]')
                for (var i = 0; i < dialogs.length; i++) {
                  var dialog = dialogs[i]
                  if (!dialog.querySelector('input[type="password"][required]')) continue
                  var rows = dialog.querySelectorAll('div')
                  for (var j = 0; j < rows.length; j++) {
                    var row = rows[j]
                    if (row.children.length !== 2) continue
                    var first = row.children[0]
                    var second = row.children[1]
                    if (first.tagName !== 'BUTTON' || second.tagName !== 'BUTTON') continue
                    var buttons = [first, second]
                    for (var k = 0; k < buttons.length; k++) {
                      // 清掉上一次由 Glass 写入的宽度，重新依据上游样式
                      // 与当前文案测量。
                      buttons[k].style.width = ''
                      buttons[k].style.minWidth = ''
                      buttons[k].style.height = ''
                      buttons[k].style.minHeight = ''
                    }
                    var width = Math.ceil(Math.max(
                      first.getBoundingClientRect().width,
                      second.getBoundingClientRect().width,
                    ))
                    var height = Math.ceil(Math.max(
                      first.getBoundingClientRect().height,
                      second.getBoundingClientRect().height,
                    ))
                    for (var m = 0; m < buttons.length; m++) {
                      buttons[m].style.boxSizing = 'border-box'
                      buttons[m].style.width = width + 'px'
                      buttons[m].style.minWidth = width + 'px'
                      buttons[m].style.height = height + 'px'
                      buttons[m].style.minHeight = height + 'px'
                    }
                  }
                }
              }
              var dshActionEqualizePending = false
              function dshScheduleCredentialActionEqualization() {
                if (dshActionEqualizePending) return
                dshActionEqualizePending = true
                requestAnimationFrame(function () {
                  dshActionEqualizePending = false
                  dshEqualizeCredentialOnboardingActions()
                })
              }
              dshScheduleCredentialActionEqualization()
              if (document.fonts && document.fonts.ready) {
                document.fonts.ready.then(dshScheduleCredentialActionEqualization)
              }
              var dshMo = new MutationObserver(function () {
                dshScheduleCredentialActionEqualization()
              })
              dshMo.observe(document.body, { childList: true, subtree: true })

              // 原生同步窗口需要匹配 Harness 当前选择的主题，而不是 macOS
              // 系统主题。只传递一个布尔值，不读取也不改写任何设置内容。
              function dshPublishTheme() {
                try {
                  window.webkit.messageHandlers.dshHarnessTheme.postMessage({
                    dark: document.body.hasAttribute('data-ds-dark-theme')
                  })
                } catch (_) {}
              }
              dshPublishTheme()
              var dshThemeObserver = new MutationObserver(dshPublishTheme)
              dshThemeObserver.observe(document.body, {
                attributes: true,
                attributeFilter: ['data-ds-dark-theme']
              })
            })()
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(script)
        webView = WKWebView(frame: .zero, configuration: config)
        super.init(nibName: nil, bundle: nil)
        config.userContentController.add(self, name: "dshHarnessTheme")
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        contrastObserver = NotificationCenter.default.addObserver(
            forName: DynamicContrast.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyContrast()
        }
        webView.load(URLRequest(url: url))
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    deinit {
        if let contrastObserver {
            NotificationCenter.default.removeObserver(contrastObserver)
        }
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: "dshHarnessTheme")
    }

    override func loadView() {
        view = webView
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        applyContrast()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "dshHarnessTheme",
              let body = message.body as? [String: Any],
              let dark = body["dark"] as? Bool
        else { return }
        DispatchQueue.main.async {
            HarnessTheme.shared.setDark(dark)
        }
    }

    // MARK: 下载支持（Session log 等文件直接落盘到"下载"文件夹）

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
        } else {
            decisionHandler(.download)
        }
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        var dest = dir.appendingPathComponent(suggestedFilename)
        // 同名文件自动加序号，避免覆盖
        var counter = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            let base = (suggestedFilename as NSString).deletingPathExtension
            let ext = (suggestedFilename as NSString).pathExtension
            dest = dir.appendingPathComponent(
                ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)")
            counter += 1
        }
        completionHandler(dest)
    }

    func downloadDidFinish(_ download: WKDownload) {
        appendLog("[download] 完成：\(download.originalRequest?.url?.lastPathComponent ?? "file")\n")
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        appendLog("[download] 失败：\(error.localizedDescription)\n")
    }

    private func appendLog(_ text: String) {
        let path = BackendController.shared.logPath
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile()
            h.write(Data(text.utf8))
            try? h.close()
        } else {
            try? Data(text.utf8).write(to: URL(fileURLWithPath: path))
        }
    }

    /// 把动态反色文字颜色推进页面（初始 + 每次背景亮度变化）。
    private func applyContrast() {
        let js = DynamicContrast.shared.jsPayload
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

}

struct GlassWebView: NSViewControllerRepresentable {
    let url: URL
    func makeNSViewController(context: Context) -> GlassWebViewController {
        GlassWebViewController(url: url)
    }
    func updateNSViewController(_ vc: GlassWebViewController, context: Context) {}
}

// MARK: - 窗口配置器（在布局时机直接配置 NSWindow，确保内容+玻璃顶到窗口最顶端）

/// 挂进窗口后立刻把窗口配置成"透明+全尺寸内容"，保证玻璃覆盖到窗口最顶端。
struct WindowAnchorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let window = v.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.layoutIfNeeded()
        }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
}

// MARK: - 界面

struct ContentView: View {
    @ObservedObject var backend = BackendController.shared

    var body: some View {
        Group {
            if let url = backend.url {
                GlassWebView(url: url)
            } else if let err = backend.errorText {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                    Text("DeepSeek Harness 启动失败")
                        .font(.title2.bold())
                    Text(err)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Button("重新启动") { backend.start() }
                        .controlSize(.large)
                }
                .padding(40)
            } else {
                ProgressView("正在启动 DeepSeek Harness…")
                    .controlSize(.large)
            }
        }
        .background(
            WindowAnchorView()
                .frame(width: 0, height: 0)
        )
        // 后端重启时页面会短暂切换成 ProgressView。明确占满父视图，
        // 避免 NSHostingView 以该视图的固有尺寸缩回窗口内容区域。
        .frame(
            minWidth: 880, maxWidth: .infinity,
            minHeight: 600, maxHeight: .infinity
        )
    }
}

/// NSHostingView 子类：安全区归零，SwiftUI 内容与玻璃效果铺满整个窗口，
/// 覆盖标题栏拖动条区域（诊断显示系统默认报 safeAreaInsets.top = 32）。
final class ZeroSafeAreaHostingView<Content: View>: NSHostingView<Content> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    /// SwiftUI 在 WebView ↔ ProgressView 切换时会重新计算内容的理想大小。
    /// 根宿主不应把这个理想大小反馈给 NSWindow，否则最大化/全屏窗口可能
    /// 在同步重启后缩回初始内容高度。
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

// MARK: - App 入口（AppKit 手工建窗：styleMask 从一开始就带 fullSizeContentView，
//         确保内容+玻璃顶到窗口最顶端，覆盖标题栏拖动条）

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private struct WindowPresentation {
        let frame: NSRect
        let wasFullScreen: Bool
    }

    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    /// 同步会下载并构建完整官方 workspace；同时只能运行一个实例。
    private var syncInFlight = false
    private var syncMenuItems: [NSMenuItem] = []
    private var latestOfficialRuntimeSyncProgress = OfficialRuntimeSyncProgress.checkingLatest()
    private var syncPanel: OfficialRuntimeSyncPanelController?
    private var syncStartPresentation: WindowPresentation?
    private var pendingRestartPresentation: WindowPresentation?
    private var pendingSyncResult: (title: String, text: String, success: Bool)?
    private var backendReadyObserver: NSObjectProtocol?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DynamicContrast.shared.setLuminance(0.5)
        installSignalHandlers()
        buildMenu()
        buildWindow()
        observeBackendReadiness()
        setupTray()
        startBackdropSampling()
        BackendController.shared.start()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 手工创建窗口：fullSizeContentView 在创建时生效，内容真正铺满整窗。
    private func buildWindow() {
        let content = ContentView()
            .ignoresSafeArea()
            .glassEffect(.regular, in: .rect(cornerRadius: 14, style: .continuous))
            .frame(minWidth: 880, minHeight: 600)

        let hosting = ZeroSafeAreaHostingView(rootView: content)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "DeepSeek Harness"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.contentMinSize = NSSize(width: 880, height: 600)
        window.contentView = hosting
        hosting.frame = window.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)

        // 几何诊断：窗口各层边界写进日志，用于定位顶部"玻璃差一截"的问题。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.logGeometry()
        }
    }

    private func observeBackendReadiness() {
        backendReadyObserver = NotificationCenter.default.addObserver(
            forName: BackendController.didBecomeReady,
            object: BackendController.shared,
            queue: .main
        ) { [weak self] _ in
            self?.restorePresentationAfterBackendRestart()
        }
    }

    private func captureWindowPresentation() -> WindowPresentation {
        WindowPresentation(
            frame: window.frame,
            wasFullScreen: window.styleMask.contains(.fullScreen)
        )
    }

    /// 同步会重建 WebView；恢复同步前的主窗口几何，避免 SwiftUI 的临时
    /// ProgressView 固有尺寸把最大化窗口缩回普通高度。
    private func restorePresentationAfterBackendRestart() {
        guard let presentation = pendingRestartPresentation else { return }
        pendingRestartPresentation = nil

        let needsFullScreenRestore = presentation.wasFullScreen
            && !window.styleMask.contains(.fullScreen)
        if needsFullScreenRestore {
            window.toggleFullScreen(nil)
        } else {
            window.setFrame(presentation.frame, display: true)
        }

        refreshMainWindowLayout()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.refreshMainWindowLayout()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (needsFullScreenRestore ? 0.75 : 0.30)) {
            [weak self] in
            guard let self else { return }
            self.refreshMainWindowLayout()
            if let result = self.pendingSyncResult {
                self.pendingSyncResult = nil
                self.showPluginResult(
                    title: result.title,
                    text: result.text,
                    success: result.success
                )
            }
        }
    }

    private func refreshMainWindowLayout() {
        window.contentView?.needsLayout = true
        window.contentView?.layoutSubtreeIfNeeded()
        window.layoutIfNeeded()
        logGeometry()
    }

    // MARK: 背景亮度采样（动态反色文字）

    private var wallpaperURL: URL?
    private var wallpaperSmall: NSBitmapImageRep?
    private var sampleTimer: Timer?

    private func startBackdropSampling() {
        sampleBackdrop()
        // 只在启动和每 60 秒检查一次壁纸变化（换壁纸时重新决策一次）。
        // 不再跟随窗口位置：拖动窗口不会改变文字颜色（苹果原则：大表面不翻转）。
        sampleTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.sampleBackdrop()
        }
    }

    /// 采样整张壁纸的平均亮度（0=暗 1=亮），驱动文字反色。窗口位置无关。
    private func sampleBackdrop() {
        guard let screen = window?.screen ?? NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return }
        if url != wallpaperURL {
            wallpaperURL = url
            wallpaperSmall = Self.downsample(URL: url)
        }
        guard let rep = wallpaperSmall else { return }
        guard let L = Self.averageLuminance(
            rep, x0: 0, y0: 0, x1: rep.pixelsWide, y1: rep.pixelsHigh
        ) else { return }
        DynamicContrast.shared.setLuminance(L)
        diagLog("[backdrop] luminance=\(String(format: "%.2f", L))")
    }

    private static func downsample(URL url: URL) -> NSBitmapImageRep? {
        guard let img = NSImage(contentsOf: url) else { return nil }
        let w = 96
        let h = max(1, Int(Double(w) * (img.size.height / max(img.size.width, 1))))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func averageLuminance(
        _ rep: NSBitmapImageRep, x0: Int, y0: Int, x1: Int, y1: Int
    ) -> Double? {
        guard x1 > x0, y1 > y0, let data = rep.bitmapData else { return nil }
        let bpr = rep.bytesPerRow
        var total = 0.0
        var count = 0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = y * bpr + x * 4
                let r = Double(data[i]) / 255.0
                let g = Double(data[i + 1]) / 255.0
                let b = Double(data[i + 2]) / 255.0
                total += 0.2126 * r + 0.7152 * g + 0.0722 * b
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return total / Double(count)
    }

    /// 诊断行写日志（best-effort）。
    private func diagLog(_ line: String) {
        let text = line + "\n"
        if let h = FileHandle(forWritingAtPath: BackendController.shared.logPath) {
            h.seekToEndOfFile()
            h.write(Data(text.utf8))
            try? h.close()
        } else {
            try? Data(text.utf8).write(to: URL(fileURLWithPath: BackendController.shared.logPath))
        }
    }

    private func logGeometry() {
        guard let w = window, let cv = w.contentView else { return }
        let lines = [
            "window.frame=\(w.frame)",
            "contentView.frame=\(cv.frame)",
            "contentLayoutRect=\(w.contentLayoutRect)",
            "styleMask=0x\(String(w.styleMask.rawValue, radix: 16)) fullSize=\(w.styleMask.contains(.fullSizeContentView))",
            "titleVisibility=\(w.titleVisibility.rawValue)",
            "cv.safeAreaInsets=\(cv.safeAreaInsets)",
            "cv.frame-in-layout=\(w.contentLayoutRect.height - cv.frame.height)",
        ]
        let text = "[geometry] " + lines.joined(separator: " | ") + "\n"
        FileHandle.standardError.write(Data(text.utf8))
        if let h = FileHandle(forWritingAtPath: BackendController.shared.logPath) {
            h.seekToEndOfFile()
            h.write(Data(text.utf8))
            try? h.close()
        } else {
            try? Data(text.utf8).write(to: URL(fileURLWithPath: BackendController.shared.logPath))
        }
    }

    /// 手工菜单：关于/退出 + Harness 快捷入口。
    private func buildMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "关于 DeepSeek Harness",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "退出 DeepSeek Harness",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // 手工搭建 NSMenu 时，必须显式保留标准 Edit 菜单。WKWebView 会把
        // copy:/paste: 等 action 实现为 responder chain 的一部分；若缺少这些
        // 无 target 的菜单项，AppKit 就不会将 ⌘C、⌘V 等键盘事件分发给网页。
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.autoenablesItems = true
        editMenu.addItem(
            withTitle: "撤销",
            action: Selector(("undo:")),
            keyEquivalent: "z")
        let redoItem = editMenu.addItem(
            withTitle: "重做",
            action: Selector(("redo:")),
            keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = NSEvent.ModifierFlags([.command, .shift])
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "剪切",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x")
        editMenu.addItem(
            withTitle: "拷贝",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c")
        editMenu.addItem(
            withTitle: "粘贴",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "全选",
            action: #selector(NSResponder.selectAll(_:)),
            keyEquivalent: "a")
        editMenu.addItem(.separator())
        let findItem = editMenu.addItem(
            withTitle: "查找…",
            action: #selector(NSResponder.performTextFinderAction(_:)),
            keyEquivalent: "f")
        findItem.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        let findNextItem = editMenu.addItem(
            withTitle: "查找下一个",
            action: #selector(NSResponder.performTextFinderAction(_:)),
            keyEquivalent: "g")
        findNextItem.tag = Int(NSFindPanelAction.next.rawValue)
        let findPreviousItem = editMenu.addItem(
            withTitle: "查找上一个",
            action: #selector(NSResponder.performTextFinderAction(_:)),
            keyEquivalent: "g")
        findPreviousItem.keyEquivalentModifierMask = NSEvent.ModifierFlags([.command, .shift])
        findPreviousItem.tag = Int(NSFindPanelAction.previous.rawValue)
        editMenuItem.submenu = editMenu

        let harnessMenuItem = NSMenuItem()
        mainMenu.addItem(harnessMenuItem)
        let harnessMenu = NSMenu(title: "Harness")
        let syncItem = harnessMenu.addItem(
            withTitle: "同步官方 Harness…",
            action: #selector(AppDelegate.syncOfficialHarness(_:)),
            keyEquivalent: "")
        syncItem.target = self
        syncMenuItems.append(syncItem)
        harnessMenu.addItem(
            withTitle: "重启后端服务",
            action: #selector(AppDelegate.restartBackend(_:)),
            keyEquivalent: "r")
        harnessMenu.addItem(
            withTitle: "在浏览器中打开",
            action: #selector(AppDelegate.openInBrowser(_:)),
            keyEquivalent: "")
        harnessMenu.addItem(.separator())
        let pluginMenuItem = NSMenuItem(title: "插件", action: nil, keyEquivalent: "")
        let pluginMenu = NSMenu(title: "插件")
        pluginMenu.addItem(
            withTitle: "安装插件包…",
            action: #selector(AppDelegate.installPlugin(_:)),
            keyEquivalent: "")
        pluginMenu.addItem(
            withTitle: "移除插件包…",
            action: #selector(AppDelegate.removePlugin(_:)),
            keyEquivalent: "")
        pluginMenu.addItem(.separator())
        pluginMenu.addItem(
            withTitle: "打开 Web Profile 目录",
            action: #selector(AppDelegate.openWebProfile(_:)),
            keyEquivalent: "")
        pluginMenuItem.submenu = pluginMenu
        harnessMenu.addItem(pluginMenuItem)
        harnessMenu.addItem(.separator())
        harnessMenu.addItem(
            withTitle: "打开配置目录（DSH_HOME）",
            action: #selector(AppDelegate.openHome(_:)),
            keyEquivalent: "")
        harnessMenu.addItem(
            withTitle: "打开后端日志",
            action: #selector(AppDelegate.openLog(_:)),
            keyEquivalent: "")
        harnessMenuItem.submenu = harnessMenu

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(
            withTitle: "最小化",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m")
        windowMenu.addItem(
            withTitle: "关闭窗口",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func openHome(_ sender: Any?) {
        let home = BackendController.shared.homePath
        try? FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: home))
    }

    @objc private func openLog(_ sender: Any?) {
        NSWorkspace.shared.open(URL(fileURLWithPath: BackendController.shared.logPath))
    }

    @objc private func openWebProfile(_ sender: Any?) {
        let home = BackendController.shared.homePath
        let path = (home as NSString).appendingPathComponent("profiles/web")
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func installPlugin(_ sender: Any?) {
        promptForPlugin(command: "add", title: "安装 Harness 插件", actionLabel: "安装")
    }

    @objc private func removePlugin(_ sender: Any?) {
        promptForPlugin(command: "remove", title: "移除 Harness 插件", actionLabel: "移除")
    }

    /// 为官方 `dsh plugin --profile web <pnpm command> <spec>` 收集一个包 spec。
    /// 只接受单一 spec，避免把 UI 输入意外扩展成任意 shell 参数。
    private func promptForPlugin(command: String, title: String, actionLabel: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = command == "add"
            ? "输入 npm 包名或版本 spec。将由 App 内置的固定版本 pnpm 安装到 Web Profile。"
            : "输入要从 Web Profile 移除的 npm 包名。"
        let input = NSTextField(string: "")
        input.placeholderString = command == "add"
            ? "@scope/dsh-plugin@1.2.3"
            : "@scope/dsh-plugin"
        input.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        alert.accessoryView = input
        alert.addButton(withTitle: actionLabel)
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let spec = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spec.isEmpty, spec.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            showPluginResult(
                title: "\(actionLabel)插件失败",
                text: "请输入一个不含空格的 npm package spec。",
                success: false
            )
            return
        }

        BackendController.shared.runPluginCommand([command, spec]) { [weak self] success, output in
            guard let self else { return }
            if success && BackendController.shared.ownsBackend {
                BackendController.shared.restart()
            }
            let restartMessage: String
            if success {
                restartMessage = BackendController.shared.ownsBackend
                    ? "\n\n内置 Harness 已重启，新的 Profile Bundle 会在本次启动时加载。"
                    : "\n\n当前连接的是外部 dsh 实例；请重启该实例以加载 Profile Bundle。"
            } else {
                restartMessage = ""
            }
            self.showPluginResult(
                title: success ? "插件\(actionLabel)完成" : "\(actionLabel)插件失败",
                text: (output.isEmpty ? "官方 dsh plugin 已完成。" : output) + restartMessage,
                success: success
            )
        }
    }

    private func showPluginResult(title: String, text: String, success: Bool) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = success ? .informational : .warning
        alert.addButton(withTitle: "好")
        if window.isVisible {
            alert.beginSheetModal(for: window) { _ in }
        } else {
            alert.runModal()
        }
    }

    /// 被 kill/SIGINT 时也走优雅退出：先杀掉 dsh 子进程，不留孤儿。
    private func installSignalHandlers() {
        signal(SIGTERM) { _ in
            BackendController.shared.shutdown()
            exit(0)
        }
        signal(SIGINT) { _ in
            BackendController.shared.shutdown()
            exit(0)
        }
    }

    // MARK: 托盘常驻 + 关窗隐藏

    /// 关闭窗口只是隐藏，后端继续在后台运行（托盘常驻）。
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    /// 点击 Dock 图标重新显示窗口。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupTray() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            // 托盘图标：dsh 官方小鱼 logo（模板图，自动适配菜单栏深浅色）
            if let fishURL = Bundle.main.url(forResource: "fish", withExtension: "svg"),
               let fish = NSImage(contentsOf: fishURL) {
                fish.size = NSSize(width: 19, height: 19 * 17.04 / 23.16)
                fish.isTemplate = true
                button.image = fish
            } else {
                button.image = NSApp.applicationIconImage
                button.image?.size = NSSize(width: 18, height: 18)
            }
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "显示 DeepSeek Harness",
                     action: #selector(showWindowAction(_:)), keyEquivalent: "")
        let syncItem = menu.addItem(
            withTitle: "同步官方 Harness…",
            action: #selector(syncOfficialHarness(_:)),
            keyEquivalent: "")
        syncItem.target = self
        syncMenuItems.append(syncItem)
        menu.addItem(withTitle: "在浏览器中打开",
                     action: #selector(openInBrowser(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "重启后端服务",
                     action: #selector(restartBackend(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        let pluginMenuItem = NSMenuItem(title: "插件", action: nil, keyEquivalent: "")
        let pluginMenu = NSMenu(title: "插件")
        pluginMenu.addItem(withTitle: "安装插件包…",
                           action: #selector(installPlugin(_:)), keyEquivalent: "")
        pluginMenu.addItem(withTitle: "移除插件包…",
                           action: #selector(removePlugin(_:)), keyEquivalent: "")
        pluginMenu.addItem(withTitle: "打开 Web Profile 目录",
                           action: #selector(openWebProfile(_:)), keyEquivalent: "")
        pluginMenuItem.submenu = pluginMenu
        menu.addItem(pluginMenuItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "打开配置目录（DSH_HOME）",
                     action: #selector(openHome(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "打开后端日志",
                     action: #selector(openLog(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 DeepSeek Harness",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    /// 同步到官方 GitHub `master` 的精确 commit。构建完成后只切换用户级 runtime
    /// 的 `current` 符号链接；失败时仍保留正在使用的内置/上一次成功运行时。
    @objc private func syncOfficialHarness(_ sender: Any?) {
        guard !syncInFlight else { return }
        syncInFlight = true
        // 必须在显示原生同步面板之前记录。全屏空间中的浮动窗口可能改变
        // 主窗口 frame；后端重启完成后以这个快照恢复。
        syncStartPresentation = captureWindowPresentation()
        latestOfficialRuntimeSyncProgress = .checkingLatest()
        let panel = OfficialRuntimeSyncPanelController(parentWindow: window)
        syncPanel = panel
        panel.update(latestOfficialRuntimeSyncProgress)
        panel.show()
        updateSyncMenuItems()

        BackendController.shared.syncOfficialRuntime { [weak self] state in
            guard let self else { return }
            self.latestOfficialRuntimeSyncProgress = state
            self.syncPanel?.update(state)
        } completion: { [weak self] success, output in
            guard let self else { return }
            self.syncInFlight = false
            self.updateSyncMenuItems()
            self.syncPanel?.closePanel()
            self.syncPanel = nil

            var text = output
            if success {
                if BackendController.shared.ownsBackend {
                    self.pendingRestartPresentation = self.syncStartPresentation
                    self.syncStartPresentation = nil
                    BackendController.shared.restart()
                    text += "\n\n内置 Harness 已重启，新的官方运行时已生效。"
                    // 后端真正给出新 URL、并恢复窗口几何后才显示完成提示。
                    self.pendingSyncResult = (
                        title: "官方 Harness 同步完成",
                        text: text,
                        success: true
                    )
                    return
                } else {
                    text += "\n\n已更新 App 的内置运行时；当前连接的是外部 dsh 实例，"
                        + "不会替换它。下次由 App 启动的内置 Harness 将使用新版本。"
                }
            } else {
                text += "\n\n已保留当前可用的 Harness 运行时。"
            }
            self.syncStartPresentation = nil

            self.showPluginResult(
                title: success ? "官方 Harness 同步完成" : "官方 Harness 同步失败",
                text: text,
                success: success
            )
        }
    }

    private func updateSyncMenuItems() {
        let title = syncInFlight ? "正在同步官方 Harness…" : "同步官方 Harness…"
        for item in syncMenuItems {
            item.title = title
            item.isEnabled = !syncInFlight
        }
    }

    private func showWindow() {
        guard let w = window else { return }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showWindowAction(_ sender: Any?) {
        showWindow()
    }

    @objc private func openInBrowser(_ sender: Any?) {
        guard let u = BackendController.shared.url else { return }
        NSWorkspace.shared.open(u)
    }

    @objc private func restartBackend(_ sender: Any?) {
        BackendController.shared.restart()
    }
}
