# OpenP2P HarmonyOS 编译指南

本文档说明如何从 OpenP2P 源码构建 HarmonyOS/OpenHarmony arm64 动态库、验证构建产物、将产物放入原生 ArkTS 工程，并最终编译 HAP。

本文面向一般开发环境，不依赖某台开发机的固定用户名或盘符。示例中的路径请按实际环境替换。

## 1. 工程结构与产物流向

仓库中与 HarmonyOS 构建直接相关的目录如下：

```text
openp2p-master/
├── cmd/
│   └── openp2p_ohos.go             # OpenHarmony Go/C 导出入口
├── core/
│   ├── ohos_platform.go
│   ├── optun_ohos.go
│   └── util_ohos.go                # OHOS 平台实现
├── go.mod
├── go.sum
└── ohos/
    ├── build-profile.json5         # HarmonyOS SDK、产品和签名配置
    └── entry/
        ├── libs/
        │   └── arm64-v8a/
        │       ├── libopenp2p_ohos.so
        │       └── libopenp2p_ohos.h
        └── src/main/cpp/
            ├── CMakeLists.txt
            └── napi_init.cpp       # ArkTS 与 OpenP2P 的 NAPI 桥
```

完整产物流向：

```text
OpenHarmony-SIG Go + OHOS Native SDK + OpenP2P Go 源码
                              │
                              ▼
             libopenp2p_ohos.so + libopenp2p_ohos.h
                              │
                              ▼
                 ohos/entry/libs/arm64-v8a/
                              │
                              ▼
       Hvigor + CMake 编译 napi_init.cpp，生成 libentry.so
                              │
                              ▼
       HAP 打包 libentry.so、libopenp2p_ohos.so 等运行库
                              │
                              ▼
 ArkTS → libentry.so → dlopen/dlsym → libopenp2p_ohos.so
```

当前工程是原生 ArkTS 前端，不需要 Flutter SDK，也不需要执行 `flutter pub get`。

## 2. 当前构建基线

| 项目 | 当前配置 | 说明 |
| --- | --- | --- |
| HarmonyOS SDK | `6.1.1(24)` | 见 `ohos/build-profile.json5` |
| 应用运行时 | HarmonyOS | 原生 ArkTS Stage 模型 |
| OpenHarmony Go | `release-branch.go1.24` | 官方仓库 `ohos_golang_go` |
| Go module | `go 1.23.1`，toolchain `go1.24.5` | 见仓库根目录 `go.mod` |
| Native ABI | `arm64-v8a` | 当前只提供 arm64 动态库 |
| Go build target | `openharmony/arm64` | 不得替换为 `linux/arm64` |

SDK 版本关系必须满足：

```text
compatibleSdkVersion <= targetSdkVersion <= compileSdkVersion
```

当前项目的 `compatibleSdkVersion` 与 `targetSdkVersion` 均为 `6.1.1(24)`，因此 DevEco Studio 中用于编译的 SDK 也必须至少为 API 24。

## 3. 构建环境要求

构建分为两部分：

1. 在 Linux 上构建 OpenP2P Go 动态库；
2. 在安装了 DevEco Studio 的开发机上构建 ArkTS/HAP。

### 3.1 Linux 构建机

推荐 Ubuntu 22.04 或更新版本。安装基础工具：

```bash
sudo apt update
sudo apt install -y \
  golang-go clang lld build-essential cmake ninja-build \
  git ca-certificates binutils file
```

系统自带 Go 仅用于引导编译 OpenHarmony-SIG Go，不能直接用于生成最终 OHOS 动态库。

### 3.2 HarmonyOS 开发机

需要安装：

- DevEco Studio；
- HarmonyOS SDK 6.1.1/API 24 或更高版本；
- DevEco Studio 自带的 Hvigor、OHPM、Node.js 和 Native SDK；
- 与目标设备匹配的调试或发布签名。

`local.properties` 是本机生成文件，不应复制其他开发机的绝对路径，也不应提交到版本库。

## 4. 构建 OpenHarmony-SIG Go

OpenP2P 使用 CGO，并且 HarmonyOS 加载器对 Go TLS 模型有明确要求。必须使用支持 `GOOS=openharmony` 的 OpenHarmony-SIG Go，不能使用标准 Go 配合 `GOOS=linux` 代替。

### 4.1 获取源码

```bash
mkdir -p "$HOME/ohos-build"
cd "$HOME/ohos-build"

git clone --branch release-branch.go1.24 \
  https://gitcode.com/openharmony-sig/ohos_golang_go.git
```

仓库地址：

```text
https://gitcode.com/openharmony-sig/ohos_golang_go
```

### 4.2 构建 Go 工具链

```bash
cd "$HOME/ohos-build/ohos_golang_go/src"
export GOROOT_BOOTSTRAP="$(go env GOROOT)"
./make.bash
```

验证：

```bash
../bin/go version
../bin/go tool dist list | grep '^openharmony/arm64$'
```

必须看到：

```text
openharmony/arm64
```

建议记录工具链版本，便于复现：

```bash
git -C "$HOME/ohos-build/ohos_golang_go" rev-parse HEAD
```

## 5. 准备 Linux 可用的 OHOS Native SDK

OpenP2P 启用了 CGO，因此 Go 编译器之外还需要以下内容：

- OHOS sysroot 和系统头文件；
- AArch64 OHOS C/C++ 运行库；
- Clang resource 目录；
- compiler-rt、libunwind 和 LLD。

优先使用官方 Linux 版 OHOS Native SDK。如果只能从 Windows DevEco SDK 中提取文件，可以复制平台无关的数据目录，但不能在 Linux 中运行 `clang.exe`。

推荐目录结构：

```text
$HOME/ohos-build/ohos-native/
├── sysroot/
└── llvm/
    └── lib/
        ├── aarch64-linux-ohos/
        │   └── libunwind.a
        └── clang/<版本>/
            ├── include/
            └── lib/aarch64-linux-ohos/
                ├── clang_rt.crtbegin.o
                ├── clang_rt.crtend.o
                └── libclang_rt.builtins.a
```

如果使用系统 Clang，可创建包装器 `$HOME/ohos-build/ohos-clang`：

```sh
#!/bin/sh
set -eu

: "${OHOS_NATIVE_ROOT:?OHOS_NATIVE_ROOT is required}"
: "${OHOS_CLANG_RESOURCE_VERSION:?OHOS_CLANG_RESOURCE_VERSION is required}"

exec clang \
  --target=aarch64-linux-ohos \
  --sysroot="$OHOS_NATIVE_ROOT/sysroot" \
  -resource-dir="$OHOS_NATIVE_ROOT/llvm/lib/clang/$OHOS_CLANG_RESOURCE_VERSION" \
  "$@" \
  -L"$OHOS_NATIVE_ROOT/llvm/lib/aarch64-linux-ohos" \
  -fuse-ld=lld \
  -Wno-unused-command-line-argument
```

赋予执行权限，并从实际 SDK 目录确定 Clang resource 版本：

```bash
chmod 755 "$HOME/ohos-build/ohos-clang"

export OHOS_NATIVE_ROOT="$HOME/ohos-build/ohos-native"
ls "$OHOS_NATIVE_ROOT/llvm/lib/clang"
export OHOS_CLANG_RESOURCE_VERSION=15.0.4  # 示例，以实际目录名为准
```

先执行最小链接测试：

```bash
"$HOME/ohos-build/ohos-clang" \
  -shared -x c /dev/null \
  -o "$HOME/ohos-build/link-test.so"

file "$HOME/ohos-build/link-test.so"
```

结果应包含：

```text
ELF 64-bit ... ARM aarch64 ... shared object
```

如果使用完整 Linux 版 OHOS Native SDK，可以让 `CC` 指向 SDK 自带的 Clang 包装器，但仍要确认其目标三元组为 `aarch64-linux-ohos`。

## 6. 获取或同步 OpenP2P 源码

在 Linux 构建机上准备仓库：

```bash
cd "$HOME/ohos-build"
git clone https://github.com/Guailoudou/openp2p.git openp2p-master
cd openp2p-master
```

也可以从开发机同步工作树，但必须同步完整源码和以下文件，不能只同步单个 Go 文件：

```text
cmd/openp2p_ohos.go
core/*_ohos.go
go.mod
go.sum
```

构建前检查工作树版本：

```bash
git status --short
git rev-parse HEAD
```

如果正在验证尚未提交的改动，必须确认这些改动也已经同步到 Linux；否则生成的 SO 不会包含本地修改。

## 7. 编译 libopenp2p_ohos.so

### 7.1 设置交叉编译环境

```bash
export GOROOT="$HOME/ohos-build/ohos_golang_go"
export PATH="$GOROOT/bin:$PATH"

export GOOS=openharmony
export GOARCH=arm64
export CGO_ENABLED=1
export CC="$HOME/ohos-build/ohos-clang"

export OHOS_NATIVE_ROOT="$HOME/ohos-build/ohos-native"
export OHOS_CLANG_RESOURCE_VERSION=15.0.4  # 以实际 SDK 为准
```

确认所有关键值：

```bash
go version
go env GOOS GOARCH CGO_ENABLED CC GOROOT
```

预期至少包含：

```text
openharmony
arm64
1
```

如果 `GOOS` 显示为 `linux`，必须停止构建并修正环境。

### 7.2 下载依赖

```bash
cd "$HOME/ohos-build/openp2p-master"
go mod download
```

正式构建建议使用 `-mod=readonly`，防止构建过程自动修改 `go.mod` 或 `go.sum`。

### 7.3 生成动态库

```bash
mkdir -p "$HOME/ohos-build/output"

go build \
  -mod=readonly \
  -tags openharmony \
  -buildmode=c-shared \
  -trimpath \
  -ldflags=-s \
  -o "$HOME/ohos-build/output/libopenp2p_ohos.so" \
  ./cmd
```

`-buildmode=c-shared` 会一次生成两个文件：

```text
$HOME/ohos-build/output/libopenp2p_ohos.so
$HOME/ohos-build/output/libopenp2p_ohos.h
```

两个文件必须来自同一次构建：

- `libopenp2p_ohos.so`：设备运行时加载的 OpenP2P 核心；
- `libopenp2p_ohos.h`：由 cgo 生成的 C ABI 声明，用于核对导出函数签名。

当前 NAPI 桥通过 `dlsym` 动态解析符号，因此 CMake 不直接包含这个头文件，但仍应将 `.h` 与 `.so` 一起保存，避免 ABI 声明与二进制版本不一致。

调试 Go 崩溃时，可以临时移除 `-ldflags=-s` 和 `-trimpath` 以保留更多符号信息；发布构建再恢复裁剪参数。

## 8. 验证 SO 产物

不要只根据 `go build` 返回成功判断产物可用。复制回项目之前至少执行以下检查：

```bash
SO="$HOME/ohos-build/output/libopenp2p_ohos.so"

file "$SO"
readelf -h "$SO"
readelf -d "$SO"
readelf -rW "$SO" | grep -Ei 'TLS|TLSDESC' || true
nm -D --defined-only "$SO" | grep ' T OpenP2P'
sha256sum "$SO" "$HOME/ohos-build/output/libopenp2p_ohos.h"
```

### 8.1 ELF 验收标准

`readelf -h` 应满足：

```text
Class:   ELF64
Type:    DYN (Shared object file)
Machine: AArch64
```

当前已验证产物的动态依赖只有：

```text
libc.so
```

如果出现 Linux glibc 的加载器或宿主机库，例如 `libc.so.6`、`ld-linux-aarch64.so.1`，说明使用了错误的 Linux 工具链。

### 8.2 TLS 验收标准

OpenHarmony Go 产物应使用加载器支持的动态 TLS 模型，例如 AArch64 `TLSDESC`。不能使用 stock Go 的 Linux arm64 产物。

错误产物通常会在设备启动时报：

```text
initial-exec TLS resolves to dynamic definition
```

这种错误不能通过修改 ArkTS、CMake 或重新签名解决，必须使用 OpenHarmony-SIG Go 重新构建 SO。

### 8.3 导出符号验收标准

当前 NAPI 桥要求以下 8 个符号全部存在：

```text
OpenP2PStart
OpenP2PStop
OpenP2PGetStatus
OpenP2PGetLastError
OpenP2PGetSDWANConfig
OpenP2PGetNodeName
OpenP2PReadTun
OpenP2PWriteTun
```

任意符号缺失都会造成 `dlsym` 失败。特别是出现以下日志时，应先检查符号表：

```text
Unable to load OpenP2PStart from libopenp2p_ohos.so
```

## 9. 将产物放入 HarmonyOS 工程

把同一次构建生成的 `.so` 和 `.h` 放到：

```text
openp2p-master/ohos/entry/libs/arm64-v8a/libopenp2p_ohos.so
openp2p-master/ohos/entry/libs/arm64-v8a/libopenp2p_ohos.h
```

Linux 示例：

```bash
TARGET=/path/to/openp2p-master/ohos/entry/libs/arm64-v8a
mkdir -p "$TARGET"

cp "$HOME/ohos-build/output/libopenp2p_ohos.so" "$TARGET/"
cp "$HOME/ohos-build/output/libopenp2p_ohos.h" "$TARGET/"
```

Windows PowerShell 示例：

```powershell
$source = 'D:\path\to\output'
$target = 'D:\path\to\openp2p-master\ohos\entry\libs\arm64-v8a'

Copy-Item -LiteralPath "$source\libopenp2p_ohos.so" -Destination $target -Force
Copy-Item -LiteralPath "$source\libopenp2p_ohos.h" -Destination $target -Force
```

替换后建议再次计算哈希，确认传输过程没有拿错旧文件：

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath `
  'D:\path\to\openp2p-master\ohos\entry\libs\arm64-v8a\libopenp2p_ohos.so'
```

### 为什么必须放在这个目录

`ohos/entry/src/main/cpp/CMakeLists.txt` 会检查：

```text
entry/libs/arm64-v8a/libopenp2p_ohos.so
```

Hvigor 会把 `entry/libs/<ABI>/` 下的动态库作为对应 ABI 的 native library 打包。运行时 `libentry.so` 使用：

```cpp
dlopen("libopenp2p_ohos.so", RTLD_NOW | RTLD_GLOBAL)
```

因此：

- 文件名不能更改；
- 不能只把 SO 放在仓库根目录；
- 不能把 Linux 构建机的绝对路径写入 CMake；
- SO 的架构必须与目录 `arm64-v8a` 一致。

## 10. Windows 上再次验证 SO

可以使用 DevEco Studio SDK 自带的 LLVM 工具：

```powershell
$nativeBin = 'D:\path\to\DevEco Studio\sdk\default\openharmony\native\llvm\bin'
$so = 'D:\path\to\openp2p-master\ohos\entry\libs\arm64-v8a\libopenp2p_ohos.so'

& "$nativeBin\llvm-readelf.exe" -h $so
& "$nativeBin\llvm-readelf.exe" -d $so
& "$nativeBin\llvm-readelf.exe" -rW $so | Select-String 'TLS|TLSDESC'
& "$nativeBin\llvm-nm.exe" -D --defined-only $so | Select-String 'OpenP2P'
```

## 11. 准备原生 HarmonyOS 工程

### 11.1 使用 DevEco Studio 打开工程

打开目录：

```text
openp2p-master/ohos
```

不要打开仓库根目录作为 HarmonyOS 工程根目录。

### 11.2 检查 SDK

在 DevEco Studio 的 SDK Manager 中确认已经安装 API 24。项目配置必须保持：

```text
compatibleSdkVersion = 6.1.1(24)
targetSdkVersion     = 6.1.1(24)
compileSdkVersion    >= 6.1.1(24)
```

命令行构建时，如果系统环境中的 `DEVECO_SDK_HOME` 无效，可以只对当前终端临时设置：

```powershell
$env:DEVECO_SDK_HOME = 'D:\path\to\DevEco Studio\sdk'
```

无需为了修复单次构建而修改全局环境变量。

### 11.3 安装 OHPM 依赖

一般在 DevEco Studio 同步工程时自动完成。需要手动执行时，在 `ohos` 目录运行：

```powershell
ohpm install
```

`oh_modules` 是可重新生成的依赖目录，不应依赖其他开发机复制的缓存。

### 11.4 配置签名

通过 DevEco Studio 的 **Project Structure / Signing Configs** 创建本机调试或发布签名。

注意：

- 不要在 README、脚本或提交记录中写入证书密码、密钥库密码；
- 不要直接复用其他开发者的绝对证书路径；
- 对外发布仓库前必须检查 `build-profile.json5` 是否包含本机签名秘密。

## 12. 编译 ArkTS 与 Native Bridge

### 12.1 只做编译检查

可先只编译 ArkTS 和 CMake Native 模块，不生成最终 HAP：

```powershell
Set-Location 'D:\path\to\openp2p-master\ohos'

& 'D:\path\to\DevEco Studio\tools\hvigor\bin\hvigorw.bat' `
  --mode module `
  -p product=default `
  -p module=entry@default `
  -p buildMode=debug `
  --no-daemon `
  default@CompileArkTS
```

这一步会检查：

- ArkTS 语法和类型；
- 资源引用；
- CMake 配置；
- `entry/libs/arm64-v8a/libopenp2p_ohos.so` 是否存在；
- `napi_init.cpp` 是否能生成 `libentry.so`。

Native bridge 的中间产物通常位于：

```text
ohos/entry/build/default/intermediates/cmake/default/obj/arm64-v8a/libentry.so
```

### 12.2 构建 HAP

推荐通过 DevEco Studio 菜单构建：

```text
Build > Build Hap(s)/APP(s) > Build Hap(s)
```

也可以使用当前 Hvigor 版本提供的 HAP 任务。不同 DevEco/Hvigor 版本的任务名可能有差异，先查看任务：

```powershell
& 'D:\path\to\DevEco Studio\tools\hvigor\bin\hvigorw.bat' `
  --mode module tasklist
```

常见命令形式为：

```powershell
& 'D:\path\to\DevEco Studio\tools\hvigor\bin\hvigorw.bat' `
  --mode module `
  -p product=default `
  -p module=entry@default `
  -p buildMode=debug `
  --no-daemon `
  assembleHap
```

构建输出通常位于：

```text
ohos/entry/build/default/outputs/default/entry-default-unsigned.hap
ohos/entry/build/default/outputs/default/entry-default-signed.hap
```

是否生成 signed HAP 取决于本机签名配置。

## 13. 检查 HAP 是否包含正确动态库

完整构建后，中间打包目录应包含：

```text
ohos/entry/build/default/intermediates/libs/default/arm64-v8a/
├── libentry.so
├── libopenp2p_ohos.so
└── libc++_shared.so
```

重点确认 `libopenp2p_ohos.so` 的文件大小和 SHA-256 与刚复制到 `entry/libs/arm64-v8a` 的文件一致。若不一致，通常是旧的构建缓存仍在生效。

替换 SO 后应重新构建 HAP，并重新安装到设备。仅替换开发机文件不会改变设备上已经安装的应用。

## 14. 运行时产物如何使用

HAP 中有两层 Native 库：

| 产物 | 生成方式 | 作用 |
| --- | --- | --- |
| `libentry.so` | Hvigor/CMake 编译 `napi_init.cpp` | 向 ArkTS 暴露启动、停止、状态、SD-WAN 和 TUN API |
| `libopenp2p_ohos.so` | OpenHarmony-SIG Go 的 `c-shared` 构建 | 运行 OpenP2P Go 核心 |

启动过程：

1. ArkTS VPN Extension 调用 `libentry.so` 的 `startCore`；
2. `libentry.so` 调用 `dlopen("libopenp2p_ohos.so")`；
3. `dlsym` 解析 `OpenP2PStart` 等接口；
4. Token、运行目录、共享带宽和日志级别作为参数传入 Go 核心；
5. Go 核心在应用沙箱运行目录中写入 `log/openp2p.log`；
6. ArkTS 通过状态接口判断核心状态，并通过 TUN 接口交换 VPN 数据包。

当前前端不会直接编辑 `config.json`。Token 以十进制字符串保存于应用本地首选项中，启动核心时再作为参数传入，避免 JavaScript `number` 对 uint64 Token 造成精度损失。

## 15. 更新 OpenP2P 核心的标准流程

每次修改 Go 核心后，按以下顺序操作：

1. 将最新 OpenP2P 源码同步到 Linux；
2. 确认 `git status` 和提交版本；
3. 使用 OpenHarmony-SIG Go 重新执行 `go build -buildmode=c-shared`；
4. 验证 ELF、TLS、动态依赖和 8 个导出符号；
5. 记录 `.so` 与 `.h` 的 SHA-256；
6. 将两个文件复制到 `ohos/entry/libs/arm64-v8a`；
7. 清理或重新执行 Native/HAP 构建，避免旧缓存；
8. 检查 HAP 中打包的 SO 哈希；
9. 重新安装应用并在真机查看 `openp2p.log`。

不要只替换 `.h`，也不要把新 `.so` 与旧 `.h` 混用。

## 16. 常见错误

### 16.1 `initial-exec TLS resolves to dynamic definition`

原因：使用标准 Go、`GOOS=linux` 或错误 Clang/sysroot 构建了动态库。

处理：

1. 确认 `go tool dist list` 包含 `openharmony/arm64`；
2. 确认 `go env GOOS` 为 `openharmony`；
3. 确认 `CC` 的 target 为 `aarch64-linux-ohos`；
4. 删除错误产物并重新构建；
5. 使用 `readelf -rW` 复核 TLS relocation。

### 16.2 `Unable to load libopenp2p_ohos.so`

可能原因：

- SO 未放入 `entry/libs/arm64-v8a`；
- HAP 中仍是旧 SO 或根本没有打包 SO；
- SO 不是 AArch64；
- SO 依赖了设备不存在的 Linux 库；
- 文件在复制过程中损坏。

检查顺序：HAP 打包目录 → SHA-256 → `readelf -h` → `readelf -d` → 设备日志中的完整 `dlerror()`。

### 16.3 `Unable to load OpenP2PStart from libopenp2p_ohos.so`

原因：动态库缺少导出符号，或库本身在符号解析前加载失败。

处理：

```bash
nm -D --defined-only libopenp2p_ohos.so | grep OpenP2P
```

确认 9 个接口均存在（包括 `OpenP2PIsRunning`），并确认 `.so` 与 `.h` 来自同一次构建。

### 16.4 CMake 报 `OpenP2P OHOS library was not found`

原因：文件未放到项目约定位置。

正确位置：

```text
ohos/entry/libs/arm64-v8a/libopenp2p_ohos.so
```

### 16.5 Hvigor 报 SDK 版本关系错误

检查：

```text
compatibleSdkVersion <= targetSdkVersion <= compileSdkVersion
```

当前工程目标为 API 24，因此不能使用 API 20 等更低的 compile SDK。

### 16.6 `Invalid value of DEVECO_SDK_HOME`

当前终端临时设置正确 SDK 根目录：

```powershell
$env:DEVECO_SDK_HOME = 'D:\path\to\DevEco Studio\sdk'
```

然后重新运行 Hvigor。不要把路径设置为 `native`、`openharmony` 等子目录。

### 16.7 核心启动成功但 VPN 等待配置

如果日志包含：

```text
login ok
OhosSDWANConfig={"Nodes":null}
```

这是未分配 SD-WAN 时的正常状态，不影响端口映射。鸿蒙端的核心巡检只通过
`OpenP2PIsRunning` 判断核心实例是否存活，不把服务器暂时离线、`Nodes:null`
或未创建 TUN 当作核心故障。

巡检每 10 秒执行一次，连续 3 次确认核心停止后才恢复；恢复延迟依次为
2 秒、5 秒、15 秒和 60 秒，10 分钟内最多尝试 5 次。用户手动停止后会清除
“期望运行”状态，不会被自动拉起。持续后台任务申请失败时，应用自动退化为
仅依赖 VPN Extension，不会阻止核心启动。

说明 SO 已成功加载且 OpenP2P 已登录，但服务端尚未给当前节点下发完整 SD-WAN 配置。这不是编译或动态库加载错误，需要在服务端将当前节点加入有效 SD-WAN。

## 17. 增加其他 ABI

当前工程只支持 `arm64-v8a`。若要增加其他 ABI，必须同时完成：

1. OpenHarmony Go 支持对应的 `GOOS/GOARCH`；
2. OHOS Native SDK 提供对应 sysroot 和运行库；
3. 为该架构单独构建 SO；
4. 放入独立目录，例如 `entry/libs/<ABI>/`；
5. 更新工程 Native 架构配置；
6. 在对应架构真机上验证 TLS、加载和 TUN 数据路径。

不能把 arm64 SO 复制到其他 ABI 目录冒充对应架构。

## 18. 发布前检查清单

- [ ] 使用 OpenHarmony-SIG Go，而不是 stock Go；
- [ ] `go env GOOS GOARCH CGO_ENABLED` 为 `openharmony arm64 1`；
- [ ] `CC` 的 target 是 `aarch64-linux-ohos`；
- [ ] SO 为 `ELF64`、`AArch64`、`DYN`；
- [ ] 动态依赖没有 Linux glibc 或开发机私有库；
- [ ] 没有 initial-exec TLS 加载问题；
- [ ] 8 个 `OpenP2P*` 导出符号全部存在；
- [ ] `.so` 和 `.h` 来自同一次构建；
- [ ] 两个产物已放入 `ohos/entry/libs/arm64-v8a`；
- [ ] DevEco compile SDK 不低于 API 24；
- [ ] ArkTS/NAPI 编译成功；
- [ ] HAP 中包含新的 `libopenp2p_ohos.so`；
- [ ] HAP 内 SO 与源产物 SHA-256 一致；
- [ ] 本机签名密码和证书路径没有进入公开提交；
- [ ] 真机日志中没有 `dlopen`、`dlsym` 或 TLS relocation 错误。
