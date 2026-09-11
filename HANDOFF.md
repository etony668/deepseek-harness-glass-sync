# DeepSeek Harness Glass 交接文档

更新时间：2026-09-10

## 当前用户要求

用户要求暂时暂停 GitHub 上传和 Release 操作。

当前优先修复：

1. 同步前后出现两套官方 Harness UI。
2. 同步后选择模型时报错：

```text
gateway/internal: resume failed for session "...":
SessionAlreadyOwnedError: session "..." is already owned by an active write handle
```

## 根因

同步前，App 启动时可能直接使用 App 内置的：

```text
Contents/Resources/backend
```

同步后，App 又切换到用户目录下的：

```text
~/Library/Application Support/DeepSeek Harness Glass/runtime/current
```

因此存在两套官方 runtime 来源。同步完成时，旧 dsh 后端还没有完全退出，新 runtime 后端就开始启动；两个进程共用同一个 `DSH_HOME`，会同时持有同一 session 的写句柄，触发 `SessionAlreadyOwnedError`。

侧边栏样式不同也是同一原因：

- 同步前：App 内置旧 runtime 的侧边栏。
- 同步后：官方新 runtime 的完整版本标签侧边栏。

## 已完成的源码修改

文件：

```text
glass/Sources/main.swift
```

已加入：

### 1. 单一 runtime 来源

当 App 只能找到内置 `Resources/backend` 时，不再直接返回该目录，而是把它复制到：

```text
~/Library/Application Support/DeepSeek Harness Glass/runtime/versions/<bundled-commit>
```

然后创建：

```text
~/Library/Application Support/DeepSeek Harness Glass/runtime/current
```

后续启动统一从 `runtime/current` 读取，避免同步前后切换两套来源。

### 2. 安全重启

新增：

```swift
private var restartAfterExit = false
```

调用 `restart()` 时：

- 先请求旧 dsh 进程退出；
- 不立即清空并启动新进程；
- 等旧进程的 `terminationHandler` 确认退出后，再调用 `start()`；
- 防止两个后端同时占用同一个 session。

## 之前已完成的同步构建修复

官方 Harness 新版 native system 构建要求 Node-API headers。

已修改：

```text
scripts/build-runtime.sh
glass/assemble.sh
windows/build-runtime.ps1
windows/package.ps1
```

需要同时提供：

```text
Contents/Resources/include/node/node_api.h
Contents/Resources/node/include/node/node_api.h
```

官方构建实际查找的是第一处：

```text
Contents/Resources/include/node
```

之前只放在 `Resources/node/include`，所以仍然在 56% 失败；当前已经修正为两处都打包。

## 当前构建/验证状态

之前完整官方 runtime 构建已经成功通过：

- 官方依赖安装成功；
- Web 前端构建成功；
- `@deepseek-ai/dsh` deploy 成功；
- workspace 依赖闭包整理成功；
- 官方 `dsh web` smoke test 通过；
- Node-API headers 已验证；
- macOS App 曾成功组装到：

```text
/Applications/DeepSeek Harness.app
```

当前最新 Swift runtime 单一来源修复已写入源码，但尚未重新构建 App 和执行最终启动验证。

## 当前目录状态

当前目录：

```text
/Users/etony/Documents/DeepSeek Harness Glass
```

注意：用户刚刚把源码移动到当前目录，但此目录目前没有 `.git`，因此不要在这里执行 commit/push/release。

交接后应确认：

```bash
git status --short
git remote -v
```

如果仍然没有 `.git`，需要用户把完整 Git 仓库目录重新移动过来，或者从 GitHub 仓库重新 clone 后再应用本地修改。

## 下一步

1. 在新的完整 Git 仓库目录确认 `glass/Sources/main.swift` 包含上述两项修复。
2. 运行：

```bash
git diff --check
swiftc -O -parse-as-library -target arm64-apple-macosx26.0 \
  glass/Sources/main.swift \
  -o /tmp/DeepSeekHarnessGlass
```

3. 重新构建 runtime（如 `build/node`、`build/backend` 不完整）：

```bash
./scripts/build-runtime.sh
```

4. 组装 App：

```bash
./glass/assemble.sh
```

5. 启动 App 并确认：

- `runtime/current` 存在；
- `runtime/current` 指向唯一版本；
- App 只启动一个 dsh 后端；
- 同步前后侧边栏样式一致；
- 选择模型不再出现 `SessionAlreadyOwnedError`。

6. 用户确认修复后，才继续：

- 版本更新到 `0.5.13`；
- commit/push 到 `etony668/deepseek-harness-glass-sync`；
- 触发 GitHub Windows 构建；
- 本机构建 DMG；
- 上传 macOS DMG 和 Windows ZIP/Setup 到 `v0.5.13` Release。

## 重要约束

- 不要把 `~/.dsh/plugins/dsh-task-board/` 插件源码提交到主项目。
- 不要修改官方 upstream 源码来规避问题；兼容逻辑应放在打包 runtime 或外壳层。
- 在用户确认单一 runtime 修复前，不要继续 GitHub 上传或 Release。
