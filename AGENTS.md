# OpenP2P 项目代理约束

本文件记录项目协作中已经明确确认的硬性要求。后续代理修改本仓库时必须遵守；若用户在当前任务中给出更新、更具体的指令，以用户最新指令为准。

## 1. 工作范围与操作边界

- HarmonyOS 新前端位于 `ohos/`，采用原生 ArkTS Stage 模型，不使用 Flutter 组件或 Flutter 插件实现鸿蒙界面与系统能力。
- 未经用户明确要求，不构建、签名、安装或发布 HAP。用户负责最终 HAP 编译；代理可以运行 `default@CompileArkTS` 等不打包 HAP 的检查任务。
- 未经用户明确要求，不执行 `git push`、创建远端提交或发布版本。
- 保留工作树中用户已有改动，不覆盖、回滚或顺手整理与当前任务无关的文件。
- 涉及 HarmonyOS API、组件行为或权限时，优先核对华为官方文档和当前 API 24 SDK 的类型声明，不凭旧版本经验猜测接口。



## 7. OpenHarmony Go 与 SO 产物

- `libopenp2p_ohos.so` 只能在 Linux 上使用 OpenHarmony-SIG Go 构建。不得使用标准 Go、`GOOS=linux` 或普通 Linux Clang 生成替代库。
- OpenHarmony-SIG Go 上游仓库为 `https://gitcode.com/openharmony-sig/ohos_golang_go`；构建前确认实际使用的是支持 `GOOS=openharmony` 的工具链。
- SO 目标架构为 `openharmony/arm64`，启用 CGO，并以 `-buildmode=c-shared` 同时生成：

  - `libopenp2p_ohos.so`
  - `libopenp2p_ohos.h`

- `.so` 与 `.h` 必须来自同一次编译，复制到：

  - `ohos/entry/libs/arm64-v8a/libopenp2p_ohos.so`
  - `ohos/entry/libs/arm64-v8a/libopenp2p_ohos.h`

- 替换前至少检查 ELF 为 AArch64 共享库、动态依赖和导出符号；当前必须包含 `OpenP2PIsRunning`。
- 修改 Go 核心导出接口后，必须重新编译并替换 SO，只有修改 ArkTS/NAPI 声明而沿用旧 SO 不算完成。
- 完整构建、校验和产物使用流程以 `ohos/README.md` 为准。

