# gdmpv —— libmpv 音频播放 GDExtension

把 mpv 作为独立播放引擎外挂给 Godot，用于跨平台音乐播放。上层只认 `AudioBackend` 接口（见 `docs/2026-10-27_libmpv原生扩展.md`），不直接依赖本模块。

> **当前状态**：`bin/` 下已有 macOS 与 Android arm64 产物，扩展可正常加载。
> 若在未编译 `bin/` 的机器上打开项目，会打印约 3 行
> `Can't open dynamic library ... libgdmpv.*`；这不影响项目运行
> （`AudioBackendFactory` 会自动回退到 Godot 原生播放器），编译出产物后自动消失。


## 目录

```
addons/gdmpv/
├── gdmpv.gdextension     # Godot 扩展声明
├── SConstruct            # 构建脚本
├── src/
│   ├── register_types.cpp
│   ├── gdmpv_player.h
│   └── gdmpv_player.cpp
├── bin/                  # 编译产物（.gitignore）
└── vendor/godot-cpp/     # 本地 godot-cpp 源码（.gitignore，不入库）
```

## 前置依赖

| 依赖 | 用途 | macOS 安装 |
|---|---|---|
| scons | 构建 | `brew install scons` |
| pkg-config | 探测 libmpv | 系统自带 |
| godot-cpp | Godot C++ 绑定 | 见下方 clone |
| libmpv（**LGPL 构建**） | 播放内核 | 开发期可 `brew install mpv` 快速验证 |

> ⚠️ `brew install mpv` 得到的是 **GPL 构建**，只能本地调试，**禁止随 App 分发**。正式产物必须按 `-Dgpl=false` 自编，详见手册 §6。

## 构建

```bash
# 0. 装 libmpv（开发期用 Homebrew 版，GPL，仅本地调试）
brew install mpv
export PKG_CONFIG_PATH="$(brew --prefix)/lib/pkgconfig:$PKG_CONFIG_PATH"

# 1. 准备 godot-cpp（4.6/4.7 暂无 stable tag，用 master；
#    master 已内置 gdextension/extension_api-4-7.json，无需 submodule）
git clone --depth 1 -b master https://github.com/godotengine/godot-cpp.git vendor/godot-cpp

# 2. 编译（macOS arm64 为例；api_version=4.7 必填，否则 godot-cpp master 报错）
scons platform=macos target=template_debug arch=arm64 api_version=4.7 -j8
```

产物：`bin/libgdmpv.macos.template_debug.arm64.dylib`（**带 arch 后缀**，与 `gdmpv.gdextension` 的 `macos.debug.arm64` 键对应）

### 2026-10-26 macOS 实测

| 项 | 结果 |
|---|---|
| `brew install mpv` | ✅ mpv 0.41.0，自带 `libmpv.2.dylib` + `mpv.pc` |
| godot-cpp master（2026-10-22） | ✅ 含 `extension_api-4-7.json` |
| 编译耗时 | godot-cpp 全量首次约 3 分钟（-j8） |
| `otool -L` 依赖 | `/opt/homebrew/opt/mpv/lib/libmpv.2.dylib`（绝对路径，开发期免拷贝） |
| 冒烟测试 | ✅ 14 项全过（`test/gdmpv_smoke_scene.tscn`） |
| AudioBackend 层测试 | ✅ 16 项全过（`test/audio_backend_smoke_scene.tscn`） |

冒烟测试怎么跑：

```bash
# 3 秒测试音频（fixtures/tone.m4a 只有 0.163 秒，不够测）
ffmpeg -f lavfi -i "sine=frequency=440:duration=3" -c:a aac -y /tmp/gdmpv_test_tone.m4a

SMOKE_AUDIO=/tmp/gdmpv_test_tone.m4a \
  godot --headless --path . res://addons/gdmpv/test/gdmpv_smoke_scene.tscn

SMOKE_AUDIO=/tmp/gdmpv_test_tone.m4a \
  godot --headless --path . res://addons/gdmpv/test/audio_backend_smoke_scene.tscn
```

### Android 构建（arm64，已实测通过）

```bash
# 1. 交叉编译 libmpv（内部拉 mpv-android 官方 buildscripts；
#    首次约 40 分钟到 1 小时、下载 1–2 GB）
#    构建树默认落在 $HOME/.cache/gdmpv-build/mpv-android，
#    千万不要放进项目目录（6 万文件会让 Godot 扫描卡死、导出失败）
./tools/build_android_libmpv.sh arm64

# 2. 编译 GDExtension（NDK 用 mpv-android 装好的 r30）
export ANDROID_HOME="$HOME/.cache/gdmpv-build/mpv-android/buildscripts/sdk/android-sdk-mac"
export MPV_ANDROID_PREFIX="$PWD/thirdparty/mpv-android"
scons platform=android target=template_debug arch=arm64 \
      api_version=4.7 ndk_version=30.0.16248370 -j8
```

产物：
- `bin/libgdmpv.android.template_debug.arm64.so` —— 扩展本体
- `thirdparty/mpv-android/{include,lib/arm64}` —— 链接用
- `bin/android_arm64/*.so` —— 运行时依赖（libmpv + ffmpeg + libc++_shared，已 strip）

Android 实测版本：mpv-android buildscripts 拉到的 mpv 0.41.0 系、FFmpeg 8.0 系、
构建用 NDK r30，产物 ELF `LOAD` 对齐 0x4000（16 KB 页，满足 Android 15+ 要求）。

> ⚠️ **打包陷阱 1**：`libmpv.so` 与 ffmpeg 的 `libav*.so` 必须通过
> `gdmpv.gdextension` 的 `[dependencies].android.arm64` 声明，Godot 才会一起
> 打进 APK 的 `lib/arm64-v8a/`。不声明的话 APK 里只有 `libgdmpv.so`，
> 运行时 dlopen 直接失败。
>
> ⚠️ **打包陷阱 2（踩过）**：`.gdextension` 的**段内不能写 `#` 注释**。
> Godot 4.x 的 ConfigFile 会把段内注释行粘到下一个键名上，`android.arm64`
> 变成 `"#说明文字...android.arm64"`，标签匹配不到 `android`，
> 整段依赖被**静默丢弃**（导出不报错，APK 里就是少库）。
> 注释只能写在段落标题之前或 README。
>
> ⚠️ **打包陷阱 3**：不要同时声明 `android.arm64` 与 `android.x86_64` 两段依赖。
> `find_extension_dependencies()` 命中第一个标签全匹配的段就 `break`，
> 而导出时启用的架构都算 feature，两段并存可能互相遮蔽。
>
> ⚠️ 许可证：`mpv-android` 的 app 部分是 GPL，但 `libmpv` 本身可用 `-Dgpl=false`
> 编成 LGPL。**分发前必须确认 buildscripts 产出的 libmpv.so 是 LGPL 配置**
> （检查 build 日志里 ffmpeg 是否带 `--enable-gpl`）。

导出后自检：

```bash
godot --headless --path . --export-debug "Android" builds/android/gd-music-debug.apk
unzip -l builds/android/gd-music-debug.apk | grep 'lib/arm64-v8a/'
# 应看到 libmpv.so、libav*.so、libgdmpv.*.so、libc++_shared.so
```

## 最小验证

新建一个场景，挂载脚本：

```gdscript
extends Node

func _ready() -> void:
	var p := GDMPVPlayer.new()
	add_child(p)
	if p.initialize() != OK:
		push_error("gdmpv 初始化失败: %s" % p.get_last_error())
		return
	p.finished.connect(func(): print("[gdmpv] 播放结束"))
	p.load_file("/绝对路径/测试.m4a")
	p.play()
	var t := Timer.new()
	t.timeout.connect(func(): print("pos=%.2f dur=%.2f" % [p.get_position(), p.get_duration()]))
	add_child(t)
	t.start(1.0)
```

预期：能听到声音，控制台每秒打印递增的 `pos`。

## 当前范围

- ✅ 桌面构建（macOS arm64 已实测；Windows / Linux 需在对应平台编译）
- ✅ 本地与网络 URL 播放、play / pause / seek / 位置 / 时长 / 音量
- ✅ **控制器直连流式播放（Phase 1）**：`MusicAppPlaybackStateController` 检测到
  `load_source` 后端后跳过「整首下载 → 解码 AudioStream」，把 URL 直接交给 mpv
- ✅ 时长回读：mpv 加载后 0.6s 回读 `get_duration()` 并回写 `TrackData.duration`
- ✅ seek 后位置回弹：2026-10-26 实测 mpv `time-pos` 在 seek 后立即跳到目标
  （50 ms 采样序列 `2.217→2.271→…` 单调递增，无回跳），**不需要插值补偿**
- ⏳ 缓冲态信号（`demuxer-cache-time` 可区分「卡在缓冲」与「播放中」）
- ✅ **Android arm64 交叉编译 + APK 打包（Phase 3 编译侧）**：libmpv/ffmpeg 打进
  `lib/arm64-v8a/`，`libgdmpv.so` 的 `DT_NEEDED` 全部为裸 soname，可由系统链接器解析；
  真机播放待验（本机无 adb 设备）
- ⏳ iOS 构建（Phase 4，需 macOS 上的 iOS 工具链与原生 AVAudioSession 配置）
- ⏳ 通知栏 / 锁屏控制（复用项目现有 `GDMusicBackgroundAudio` 插件）

## 注意

- 本模块**不接管** Godot `AudioServer`，UI 音效仍走原生播放器。
- mpv 实例必须在 `_exit_tree` 或场景销毁前 `shutdown()`，否则事件线程会泄漏。
