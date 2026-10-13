# HarmonyOS TUN 断开与弱网重连审查报告

审查日期：2026-08-21  
审查范围：HarmonyOS API 24 前端、N-API、OpenHarmony Go 核心的 TUN 生命周期、控制连接重连、P2P tunnel 重连  
审查方式：静态源码审查 + 本机 HarmonyOS API 24 官方文档核对；未构建、签名或安装 HAP，未连接真机复现

## 1. 结论

当前问题不只是“P2P tunnel 断开后重连慢”，而是三个生命周期各自判断健康，彼此没有形成闭环：

1. HarmonyOS `VpnConnection` 和 fd 可能仍存在；
2. Go 核心仍被 `OpenP2PIsRunning` 判定为存活；
3. P2P 控制连接或数据 tunnel 实际已经不可用。

因此 UI 可以持续显示 `vpn_ready`，系统 VPN 图标也可能仍在，但 TUN 数据已经无法通过 P2P 转发，表现为“假在线、真断流”。

优先确认的根因如下。

| 优先级 | 结论 | 影响 |
| --- | --- | --- |
| P0 | 控制连接重连等待超过 30 秒后，鸿蒙分支消费了重连事件却没有再次调度 | 核心永久离线但仍被 watchdog 判断为运行，TUN 假在线 |
| P0 | OpenHarmony 的 `optun.Start()` 不设置 `dev`，共享 `Stop()` 却直接调用 `t.dev.Close()` | 正常停止或核心恢复时可触发 nil interface panic，整个扩展进程退出 |
| P0 | 非阻塞 TUN fd 的写入错误全部被当作致命错误；EAGAIN 会把 `stopping` 置为 `true` | 短时背压即可永久停掉 TUN 桥接和 watchdog |
| P1 | 公网 IP 改变会强制清空已下发配置标记，同一 SD-WAN 配置也会销毁并重建 VPN | Wi-Fi/蜂窝切换、弱网恢复时产生不必要的 TUN 瞬断 |
| P1 | 核心重启后旧 TUN goroutine 没有可取消的生命周期，且全局队列跨代复用 | 多次恢复后出现旧/新 goroutine 争抢包、陈旧包进入新 fd、泄漏 |
| P1 | fd 真实失效时只停止循环，不销毁并重建 VPN，也不更新失败状态 | 后台永久断流，通常只有回前台后才可能由 UIAbility 间接恢复 |
| P1 | 没有调用 API 22+ 的 `protectProcessNet()` | 当服务端、peer 或中继地址命中 VPN 路由时，核心连接可能被递归送回 TUN |
| P2 | 小包发送分支忽略 `WriteBuffer` 错误 | 弱网时 tunnel 关闭最多延迟到后续心跳/读超时，增加黑洞窗口 |

## 2. 当前数据链路

发送方向：应用流量 → HarmonyOS VPN fd → ArkTS `readLoop` → N-API `readTun` → `OhosReadTun` → Go `readTunLoop` → P2P tunnel。

接收方向：P2P tunnel → Go `readNodeLoop` → `OhosWriteTun` → N-API `writeTun` → ArkTS `writeLoop` → HarmonyOS VPN fd → 应用。

控制连接重连和 P2P tunnel 重连由 Go 核心负责；`VpnConnection` 的创建、销毁和 fd 搬运由 `OplVpnExtensionAbility` 负责。普通 P2P tunnel 断开本来不需要销毁 TUN。

## 3. 发现明细

### P0-1：控制连接重连事件会丢失

证据：

- [`core/p2pnetwork.go`](../core/p2pnetwork.go) 第 213-246 行消费 `restartCh`，等待 `wgReconnect` 最多 30 秒。
- 第 230-235 行超时后，桌面端退出进程；`isAndroid()` 对 OpenHarmony 也返回 `true`，所以鸿蒙直接 `continue`。
- `continue` 之前没有把重连事件重新放回 `restartCh`，也没有再次调用 `pn.init()`。
- [`core/common.go`](../core/common.go) 第 308-316 行确认 OpenHarmony 被归入 `isAndroid()` 分支。
- [`cmd/openp2p_ohos.go`](../cmd/openp2p_ohos.go) 第 145-154 行和 [`core/openp2p.go`](../core/openp2p.go) 第 184-199 行只判断核心实例是否存在，不判断 `pn.online`。

弱网触发链：

1. WebSocket 读写异常调用 `pn.close(false)`；
2. `restartCh` 被 `pn.run()` 消费；
3. 旧读协程或初始化协程在 30 秒内未结束；
4. 鸿蒙分支 `continue`，重连事件丢失；
5. `pn.online=false`，但 `IsModuleRunning()` 仍返回 `true`；
6. ArkTS watchdog 不恢复核心，VPN fd 继续存在，形成永久黑洞。

解决方案：超时后必须保留重连意图。最小改动是在移动端分支重新投递一个有界 `restartCh` 事件，再进入下一轮等待；同时在 shutdown 时退出。不要在 30 秒超时后静默 `continue`。

验收：阻断控制 WebSocket 45 秒再恢复网络，120 秒内 `pn.online` 必须恢复，且 TUN fd/generation 不变化。

### P0-2：OpenHarmony `optun.Stop()` 可直接 panic

证据：

- [`core/optun_ohos.go`](../core/optun_ohos.go) 第 21 行的 `Start()` 直接返回，未给 `t.dev` 赋值。
- [`core/optun.go`](../core/optun.go) 第 17-20 行无条件调用 `t.dev.Close()`。
- [`core/p2pnetwork.go`](../core/p2pnetwork.go) 第 1081-1095 行在 `StopModule()` 路径调用 `pn.sdwan.tun.Stop()`。
- ArkTS watchdog 恢复在 [`OplVpnExtensionAbility.ets`](entry/src/main/ets/vpn/OplVpnExtensionAbility.ets) 第 705 行先调用 `stopCore()`，会进入上述路径。

结果：正常停止、扩展销毁或 watchdog 恢复都可能造成 Go panic，而不是可控停止。该问题会直接表现为 VPN/TUN 突然消失。

解决方案：不要只加 `if t.dev != nil` 后结束。OpenHarmony 的 `Stop()` 还必须取消 `readTunLoop`/`readNodeLoop`。应把 `Stop()` 做成平台实现，并给 OHOS `optun` 增加 per-instance `done` 信号；`Read`、`Write` 和两个 SD-WAN 循环收到停止信号后退出。这样同时解决 panic 和恢复后的 goroutine 泄漏。

验收：连续执行 20 次启动/停止与 5 次核心自动恢复，无 panic；每次停止后旧 TUN 读写循环均结束。

### P0-3：非阻塞写 EAGAIN 被误判为 TUN 致命故障

证据：

- [`OplVpnExtensionAbility.ets`](entry/src/main/ets/vpn/OplVpnExtensionAbility.ets) 第 471-478 行明确配置 `isBlocking: false`。
- 第 542-547 行读取侧把 `13900010`（Try again）和 `13900034`（Operation would block）视为正常。
- 第 555-575 行写入侧捕获任意异常后直接 `this.stopping = true`，没有复用同一判断。
- `stopping=true` 后读循环、写循环和 watchdog 都不再工作；没有 `destroyVpn()`、没有重建，也没有失败状态更新。

官方 API 24 文档确认：`VpnConfig.isBlocking=false` 为非阻塞模式；文件管理错误码 `13900010` 和 `13900034` 均要求重试，而不是销毁 fd。

解决方案：写入侧与读取侧统一处理 would-block：本轮停止写入，下一 tick 重试，不改变 `stopping`。只有 EBADF/EIO 等真实 fd 故障才进入串行化的 VPN 重建流程。

验收：制造 TUN 写侧背压并出现 `13900010`/`13900034` 后，状态仍为 `vpn_ready`，后续包可继续通过，watchdog 不停止。

### P1-1：物理网络变化会不必要地重建 TUN

证据：

- [`core/sdwan.go`](../core/sdwan.go) 第 324-329 行把 `previousIP != publicIP` 与 SD-WAN Gateway/CentralNode/Enable 改变放在同一 reset 条件中。
- reset 后无条件清空 `preAndroidSDWANConfig`。
- 第 331-336 行因此把服务端再次下发的相同 SD-WAN JSON 当作新配置通知 ArkTS。
- [`OplVpnExtensionAbility.ets`](entry/src/main/ets/vpn/OplVpnExtensionAbility.ets) 第 405、411-434 行每收到通知都先 `destroyVpn()`，再 `create()` 新 fd。

公网 IP、NAT 类型变化需要重建 P2P 通路，但不等于 VPN 地址、路由或 MTU 变化。当前代码把 transport 重连和 TUN 重配耦合，Wi-Fi/蜂窝切换时会主动制造 TUN 瞬断。

解决方案：

1. Go 侧公网 IP 变化可以重置 P2P app/tunnel，但不要因此清空“已通知的 VPN 配置”；
2. ArkTS 侧保留最后一次已应用的 VPN 配置指纹；地址、路由、MTU 未变时跳过 `replaceVpn()`；
3. 仅 Gateway、节点本机虚拟 IP、路由集合、MTU、Enable 等真实影响 VPN 的字段变化时重建。

验收：Wi-Fi → 蜂窝 → Wi-Fi 切换过程中，如果 SD-WAN 配置未变，`vpnGeneration` 和 fd 均不变化；P2P tunnel 允许重建。

### P1-2：核心恢复后存在跨代 goroutine 与陈旧包

证据：

- [`core/optun_ohos.go`](../core/optun_ohos.go) 第 18-19、79-82 行使用进程级全局通道。
- `Read()` 永久阻塞在 `OhosReadTun`，`Write()` 也可能永久阻塞在 `OhosWriteTun`，均没有 shutdown 分支。
- [`core/sdwan.go`](../core/sdwan.go) 第 291-305 行启动两个无限循环。
- StopModule 只尝试 `tun.Stop()`，没有等待循环退出；新核心会再创建一组循环。

解决方案：TUN 队列必须属于单个 `optun` 实例并带 generation/done；导出接口只投递到当前活动实例。停止时先取消生产和消费，再清空旧队列，等待两个循环退出，最后允许新实例接管。不要关闭仍可能被 N-API 写入的全局 channel。

验收：每次核心恢复后只有一组 TUN 读写循环；旧 generation 的包不会写入新 fd；goroutine 数不会随恢复次数单调增长。

### P1-3：真实 fd 故障没有后台自愈

证据：[`OplVpnExtensionAbility.ets`](entry/src/main/ets/vpn/OplVpnExtensionAbility.ets) 第 541-547、569-572 行只设置 `stopping=true`；第 625-627 行 watchdog 在 `stopping` 时直接返回。

解决方案：拆分“整个扩展正在停止”和“单个 VPN fd 失效”。真实 fd 错误时：

1. 标记当前 generation 失效；
2. 更新状态为 `vpn_recovering` 并记录错误码；
3. 串行执行 `destroyVpn()`；
4. 使用缓存的最后有效配置重建一次；
5. 指数退避并限制频率，超过阈值才升级为核心/扩展恢复。

这里应复用现有 recovery 限频思路，不需要新建恢复框架。

### P1-4：核心进程流量未排除 VPN 路由

证据：仓库内没有 `protectProcessNet()` 或 `protect(socketFd)` 调用。API 24 官方文档说明 `protectProcessNet()` 从 API 22 可用，会让被保护进程直接使用物理网络，避免流量再次进入 VPN。

风险：当前是分流路由，通常不会立刻自环；但当 SD-WAN resource 覆盖控制服务、peer、中继或 DNS 地址时，Go 核心自己的连接可能进入 TUN，再依赖自身转发，形成递归或黑洞。

解决方案：在 `createVpnConnection()` 后、`create(config)` 前调用一次 `await vpnConnection.protectProcessNet()`。本项目 target/compatible SDK 均为 6.1.1(24)，无需兼容旧 API。

验收：把服务端或测试 peer IP 临时放入一条 VPN resource route，控制连接仍从物理网络建立。

### P2-1：小包写错误延迟 tunnel 失效判断

证据：[`core/p2ptunnel.go`](../core/p2ptunnel.go) 第 823-829 行两个 `writeDataSmall` 分支忽略 `WriteBuffer` 返回错误，而普通数据分支第 831-837 行会关闭 tunnel。

解决方案：三个发送分支统一检查错误并调用 `t.close()`。这不是 TUN 被销毁的直接原因，但会扩大弱网黑洞窗口。

## 4. 建议实施顺序

### 第一阶段：阻止永久断流和崩溃

1. 重连等待超时后重新投递 `restartCh`，不得丢失重连意图；
2. 将 OHOS `optun.Stop()` 改为可取消、幂等、可等待的实现；
3. 写 TUN 遇到 `13900010`/`13900034` 时只重试；
4. 小包发送统一处理错误。

这四项是最小止血集，不需要改变协议或引入依赖。

### 第二阶段：解耦 TUN 与 P2P 重连

1. 同一 VPN 配置不调用 `replaceVpn()`；
2. 公网 IP/NAT 改变只重建 P2P 通路，不重建 TUN；
3. 真实 fd 故障只恢复 VPN bridge，不先重启 Go 核心；
4. 核心恢复时显式终止旧 generation 的 TUN 循环和队列。

### 第三阶段：健康检查与可观测性

现有 `OpenP2PIsRunning` 语义可以保留，但不能再把它当作完整健康状态。建议新增最小只读状态：

- `coreAlive`：Go 实例存在；
- `controlOnline`：控制 WebSocket 已登录；
- `vpnFdReady`：当前 VPN generation 有有效 fd；
- `lastPacketInMs` / `lastPacketOutMs`：定位单向断流。

`controlOnline=false` 在弱网下是正常瞬态；持续超过 90-120 秒且内部重连没有进展时，watchdog 才升级为核心恢复，避免网络抖动时反复重启。

新增 Go 导出接口后，必须按 [`ohos/README.md`](README.md) 使用 OpenHarmony-SIG Go 在 Linux 上以 `openharmony/arm64`、CGO、`-buildmode=c-shared` 同批生成并替换 `.so` 与 `.h`，再检查 AArch64 ELF、依赖和导出符号。只改 N-API/ArkTS 声明不能交付。

## 5. 弱网与切网验收矩阵

| 场景 | 操作 | 期望 |
| --- | --- | --- |
| 控制连接短断 | 丢包 100%，持续 20 秒后恢复 | 自动重新登录；TUN fd 不重建 |
| 控制连接长断 | 丢包 100%，持续 45 秒后恢复 | 重连事件不丢；120 秒内恢复；核心不假在线 |
| 单个 P2P tunnel 断开 | 只阻断 peer UDP/TCP 25 秒 | tunnel ID 可变化；TUN fd 不变化；恢复后双向通 |
| 公网 IP 改变 | Wi-Fi/蜂窝切换 | P2P/NAT 重探测；相同 SD-WAN 配置不重建 TUN |
| 配置真实改变 | 修改本机虚拟 IP、route 或 MTU | 恰好重建一次 VPN；旧 generation 停止 |
| SD-WAN 禁用/启用 | 云端 Enable 1→0→1 | 禁用时销毁；启用时只创建一组循环 |
| 非阻塞背压 | 让 fd 写出现 13900010/13900034 | 不进入 stopping；下一 tick 继续 |
| fd 被系统关闭 | 注入 EBADF/EIO | VPN bridge 有界重建；状态可见；不误杀核心 |
| 多次核心恢复 | 连续触发 5 次 | 无 panic、无重复 goroutine、无陈旧包跨代 |
| 路由自环验证 | resource 覆盖测试服务 IP | `protectProcessNet()` 后核心连接仍走物理网 |

每个场景至少记录：`requestId`、`vpnGeneration`、fd、控制连接状态、P2P tunnel ID、错误码、最后双向包时间。仅观察系统 VPN 图标不能证明链路健康。

## 6. 建议日志判据

优先搜索以下日志序列：

- `ReadMessage error` / `ReadMessage timeout`；
- `got restart channel`；
- `pn.wgReconnect.Wait() timeout`；
- 后续是否再次出现 `P2PNetwork init start` 和 `P2PNetwork init ok`；
- `VPN read failed` / `VPN write failed` 及错误码；
- `OHOS VPN interface created or refreshed` 的 fd 是否在相同配置下变化；
- `p2ptunnel close` 后是否出现新的 `buildDirectTunnel ok` 或 `buildRelayTunnel`。

判定规则：

- 有 `wgReconnect.Wait() timeout`，之后没有新的 `P2PNetwork init start`：命中 P0-1；
- `VPN write failed` 为 `13900010`/`13900034`，随后不再有桥接日志：命中 P0-3；
- 停止或自动恢复前出现 Go panic/nil pointer：优先验证 P0-2；
- 只有公网 IP 变化，却出现新的 VPN fd：命中 P1-1。

## 7. 官方 API 核对结果

通过 `devecocli docs` 核对的本机 HarmonyOS 文档：

- `@ohos.net.vpnExtension (VPN增强管理)`：`create(config)` 返回虚拟网卡 fd；不需要时应配对 `destroy()`；`isBlocking=false` 表示非阻塞；`protectProcessNet()` 从 API 22 开始支持。
- `文件管理错误码`：`13900010` 为资源暂时不可用，`13900034` 为操作被阻塞，处理方式均为重试；`13900008` 才是异常文件描述符。
- `内核错误码`：EAGAIN/EWOULDBLOCK 是可重试状态，不代表 TUN 已断开。

## 8. 审查边界

本报告确认的是源码可达缺陷和高概率故障链，尚未用真机 hilog 将某一次现场断流唯一归因到其中一项。仓库内 `ohos/Crash_87031.dmp` 未提供可直接关联上述日志的文本证据，因此未把它作为已复现证据。完成第一阶段修复后，应按第 5 节在 API 24 真机上执行弱网/切网矩阵，再决定是否需要调整 tunnel 重试退避参数。
