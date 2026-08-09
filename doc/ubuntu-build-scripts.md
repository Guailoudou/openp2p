# Ubuntu 构建脚本使用说明

本文说明如何在 Ubuntu 构建机上分别生成 OpenP2P 的 HarmonyOS 核心动态库和 Android AAR。两套脚本不会构建、签名、安装或发布 HAP/APK。

## 1. 文件与部署位置

脚本在项目中的版本：

```text
scripts/ubuntu/build-ohos.sh
scripts/ubuntu/build-android.sh
```

当前 Ubuntu 构建机上的部署位置：

```text
/home/nhd/openp2p-build-scripts/build-ohos.sh
/home/nhd/openp2p-build-scripts/build-android.sh
```

默认源码目录：

```text
/home/nhd/ohos-build/source/openp2p-master
```

每次构建都会创建带 UTC 时间和进程号的唯一输出目录，不覆盖旧产物。脚本也不会自动删除 `/tmp` 工作目录。

## 2. 构建 HarmonyOS 核心

直接使用默认路径：

```bash
/home/nhd/openp2p-build-scripts/build-ohos.sh
```

指定源码目录和输出根目录：

```bash
/home/nhd/openp2p-build-scripts/build-ohos.sh \
  /home/nhd/ohos-build/source/openp2p-master \
  /home/nhd/ohos-build/output/runs
```

也可以通过环境变量改写工具链根目录：

```bash
OPENP2P_OHOS_ROOT=/home/nhd/ohos-build \
OPENP2P_SOURCE_DIR=/home/nhd/ohos-build/source/openp2p-master \
/home/nhd/openp2p-build-scripts/build-ohos.sh
```

脚本固定执行以下保护和验收：

- 只使用 `/home/nhd/ohos-build/ohos_golang_go`，并验证其支持 `openharmony/arm64`；
- 只使用 `/home/nhd/ohos-build/ohos-clang` 交叉编译包装器；
- 使用 `GOOS=openharmony`、`GOARCH=arm64`、`CGO_ENABLED=1`；
- 使用 `-mod=readonly`，构建前后比较关键源码和 `go.mod/go.sum` 哈希；
- 检查 ELF64、AArch64、DYN 类型及动态依赖，拒绝 glibc 产物；
- 检查包括 `OpenP2PIsRunning` 在内的 9 个导出符号；
- 同一次构建生成并保存 `.so` 与 `.h`，同时写出 `SHA256SUMS`。

成功后终端会输出：

```text
OUTPUT_DIR=/home/nhd/ohos-build/output/runs/<UTC时间>-<进程号>
```

目录内容包括：

```text
libopenp2p_ohos.so
libopenp2p_ohos.h
exported-symbols.txt
source-inputs.sha256
SHA256SUMS
```

将同一次构建的 `.so` 和 `.h` 复制回当前 Windows 项目：

```powershell
$run = '/home/nhd/ohos-build/output/runs/<UTC时间>-<进程号>'
$target = 'D:\Guail\Documents\openp2p-master\ohos\entry\libs\arm64-v8a'

scp "nhd@192.168.158.131:${run}/libopenp2p_ohos.so" $target
scp "nhd@192.168.158.131:${run}/libopenp2p_ohos.h" $target
```

复制后至少运行 `default@CompileArkTS`，不要把 ArkTS 编译成功表述为 HAP 已构建。

## 3. 构建 Android AAR

直接使用默认路径：

```bash
/home/nhd/openp2p-build-scripts/build-android.sh
```

指定源码目录和输出根目录：

```bash
/home/nhd/openp2p-build-scripts/build-android.sh \
  /home/nhd/ohos-build/source/openp2p-master \
  /home/nhd/android-build/output/runs
```

可覆盖的工具链变量：

```bash
OPENP2P_ANDROID_ROOT=/home/nhd/android-build \
OPENP2P_ANDROID_SDK_ROOT=/usr/lib/android-sdk \
OPENP2P_ANDROID_NDK_ROOT=/home/nhd/android-build/android-sdk/android-ndk-r21e \
/home/nhd/openp2p-build-scripts/build-android.sh
```

Android 脚本使用：

```text
标准 Go: /home/nhd/android-build/go1.24.5
NDK:     21.4.7075529 (r21e)
SDK:     /usr/lib/android-sdk
gomobile/gobind revision: 7c4916698cc93475ebfea76748ee0faba2deb2a5
```

脚本会把源码复制到 `/tmp` 的唯一工作目录，仅修改临时副本以加入固定版本的 `golang.org/x/mobile/bind`，不会修改原始源码。构建完成后会检查：

- `runAsModule`、`stopModule`、`isModuleRunning` Java 接口；
- `armeabi-v7a`、`arm64-v8a`、`x86`、`x86_64` 四个 ABI；
- 原始 `go.mod/go.sum/core/openp2p.go` 前后哈希；
- AAR 与 source JAR 的 SHA-256。

成功输出目录包含：

```text
openp2p.aar
openp2p-sources.jar
openp2p-javap.txt
source-inputs.sha256
SHA256SUMS
```

复制到当前 Windows 项目：

```powershell
$run = '/home/nhd/android-build/output/runs/<UTC时间>-<进程号>'
$target = 'D:\Guail\Documents\openp2p-master\app\app\libs'

scp "nhd@192.168.158.131:${run}/openp2p.aar" $target
scp "nhd@192.168.158.131:${run}/openp2p-sources.jar" $target
```

然后执行 Android 检查：

```powershell
cd D:\Guail\Documents\openp2p-master\app
.\gradlew.bat :app:compileDebugKotlin
.\gradlew.bat :app:assembleDebug
```

## 4. 磁盘与临时目录

Ubuntu 根分区空间较小。两套脚本把 Go 编译缓存和临时编译文件放到 `/tmp` 的 tmpfs，减少根分区写入。

脚本遵循“不自动删除文件”的要求，因此每次都会保留并打印 `WORK_DIR`。`/tmp` 通常会在系统重启后由系统清理；连续执行多次前请先使用以下只读命令确认空间：

```bash
df -h / /tmp
du -sh /tmp/openp2p-* 2>/dev/null
```

脚本不会替用户清理旧产物、下载包或工作目录。如需清理，必须由用户明确指定准确目录后再执行。

## 5. 常见错误

### OpenHarmony 工具链目标错误

如果脚本报告不支持 `openharmony/arm64`，不得改用标准 Go 或 `GOOS=linux`。应检查 `/home/nhd/ohos-build/ohos_golang_go` 是否仍为 OpenHarmony-SIG Go。

### Android `bind` 包不可见

不要在原始源码中直接执行无版本的 `go get ...@latest`。脚本会在临时源码副本中固定使用与 `gomobile` 相同的提交。

### Android 构建提示空间不足

先执行 `df -h / /tmp`。不要未经确认删除 `/home/nhd/ohos-build`、`/home/nhd/android-build`、源码目录或历史产物。

