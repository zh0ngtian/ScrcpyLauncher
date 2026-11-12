# Scrcpy Launcher

原生 macOS App，将 scrcpy 4.1 客户端编译成动态库并在 App 主进程中运行。投屏、设置和 Dock 图标属于同一个应用，不再创建状态栏图标或独立的 scrcpy 应用进程。图标使用 scrcpy 原图，启动、投屏和退出后统一使用 App 内的 ICNS 图标，避免 SDL 在运行时替换 Dock 图标。

## 使用

1. 打开 `/Applications/Scrcpy Launcher.app`，首次从设置中选择设备，再点“保存并投屏”。
2. 以后点击 Dock 图标，直接连接已保存的序列号；投屏窗口已存在时，唤回该窗口（包含最小化的窗口）。
3. 按 `Command + ,` 打开设置，选择其他设备，可“保存默认设备”或“保存并切换投屏”。
4. 点击投屏窗口的关闭按钮（或按 `Command + W`）会停止投屏并直接退出 App。连接中或连接失败窗口的关闭按钮也会退出。按 `Command + Q` 同样可以退出。
5. 点击投屏窗口标题栏右侧的 ⏻ 电源按钮，模拟短按手机电源键，用于锁屏或唤醒设备。

只连接保存的序列号。设备离线或未授权时保留原选择，显示错误与重新连接入口。设置可刷新 USB 与无线设备列表；App 不负责无线配对。

## 运行依赖与存储

ADB 使用本机 Android Platform Tools，支持 Finder 的精简 PATH 以及 Apple Silicon / Intel Homebrew、MacPorts 标准路径。scrcpy 客户端、匹配的 server、SDL、FFmpeg 和非系统动态库随 App 打包。运行时不调用本机 `scrcpy` 可执行文件，也不依赖 Homebrew 的动态库路径。

默认设备继续使用偏好域 `dev.playphone.ScrcpyLauncher` 中的 `defaultDeviceSerial`、`defaultDeviceName`，升级不会清除。日志位于 `~/Library/Logs/dev.playphone.ScrcpyLauncher/scrcpy.log`，每次投屏覆盖。退出只停止本次 scrcpy 会话，不关闭共享 ADB server。

## 构建

需要 Xcode / Swift 6.2+，以及本机架构的构建依赖：

```sh
brew install meson ninja pkgconf ffmpeg sdl3 libusb
swift test
Scripts/package_app.sh
Scripts/launch.sh
```

产物为 `dist/Scrcpy Launcher.app`，使用本地 ad-hoc 签名。当前构建脚本面向本机架构；打包时根据原生库实际要求写入最低 macOS 版本。本机安装的 Homebrew 库要求 macOS 27，因此当前安装包也要求 macOS 27。未作 Developer ID 公证。

`Scripts/build_client.sh` 下载并校验固定版本源代码与 server 的 SHA-256。`Native/launcher.c` 将原版参数解析、视频、音频和控制接入现有 NSApplication；每次会话结束释放 SDL，以支持重新投屏和切换设备。少量上游补丁由脚本精确匹配后应用，不修改本机已安装的 scrcpy。

`Scripts/bundle_dylibs.py` 递归打包非系统依赖，改写为 App 内相对路径，并记录其实际最低系统版本。原图、scrcpy Apache-2.0 许可保存在 `Assets/`；原生库清单、Homebrew 配方与其安装目录中的许可证随 App 存放于 `Contents/Resources/Licenses/`。

## 验证

`swift test` 覆盖设备解析、默认设备持久化、扫描超时、字面序列号、会话错误、取消启动、顺序切换设备与电源键的会话状态保护。

没有手机时，可用隔离的协议模拟设备验收真正的 scrcpy 解码器、SDL 窗口和 App 菜单：

```sh
PATH="/opt/homebrew/bin:$PATH" python3 Scripts/prepare_integration_test.py
```

它启动独立标识的 `Scrcpy Integration Test.app`，模拟两台设备并传送 H.264 测试视频，不连接真实设备或更改正式 App 的偏好。可验证 `Command + ,`、切换设备、电源按钮（`control.bin` 记录按键码 26 的按下与松开）、关闭投屏窗口直接退出、最小化唤回和 `Command + Q`。退出测试 App 后，其生成产物均位于 `.build/Integration/`；测试偏好域为 `dev.playphone.ScrcpyLauncher.integration.20261111`。
