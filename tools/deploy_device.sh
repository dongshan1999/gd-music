#!/usr/bin/env bash
set -euo pipefail

# 部署脚本：把打好的 Android 包装到当前连接的设备并启动。
# 设备选择：默认使用唯一在线的设备；多设备时用 -s 指定序列号。

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ADB_BIN="${ADB_BIN:-}"
SERIAL=""
APK=""
PACKAGE=""
DO_UNINSTALL=0
DO_LAUNCH=1
SHOW_LOG=0

usage() {
  cat <<'EOF'
用法: tools/deploy_device.sh [选项]

选项:
  -s, --serial <序列号>   指定设备（adb devices 里的序列号）
  -a, --apk <path>        指定 APK，默认取 builds/android 下最新的 debug/release 包
  -k, --package <包名>    指定包名，默认读 export_presets.cfg 的 package/unique_name
  -u, --uninstall         安装前先卸载（会清掉应用数据）
  -n, --no-launch         安装后不自动启动
  -l, --log               安装后打印最近的 Godot 日志
  -h, --help              显示帮助

环境变量:
  ADB_BIN   adb 可执行文件路径，默认自动探测
  ANDROID_HOME  Android SDK 路径

示例:
  tools/deploy_device.sh                 # 装最新包并启动
  tools/deploy_device.sh -l             # 装完顺便看日志
  tools/deploy_device.sh -a builds/android/gd-music-release.apk
EOF
}

log() { printf '[deploy] %s\n' "$*"; }

# 解析 cfg/ini 里的 key=value 或 key = value，去掉两侧引号
strip_ini_value() {
  sed -e 's/^[^=]*=[[:space:]]*//' -e 's/^"//' -e 's/"[[:space:]]*$//'
}
die() {
  printf '[deploy] 错误: %s\n' "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--serial)
      [[ $# -ge 2 ]] || die "$1 需要一个参数"
      SERIAL="$2"
      shift 2
      ;;
    -a|--apk)
      [[ $# -ge 2 ]] || die "$1 需要一个参数"
      APK="$2"
      shift 2
      ;;
    -k|--package)
      [[ $# -ge 2 ]] || die "$1 需要一个参数"
      PACKAGE="$2"
      shift 2
      ;;
    -u|--uninstall)
      DO_UNINSTALL=1
      shift
      ;;
    -n|--no-launch)
      DO_LAUNCH=0
      shift
      ;;
    -l|--log)
      SHOW_LOG=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "未知参数: $1（用 -h 查看用法）"
      ;;
  esac
done

# ---------- 定位 adb ----------
resolve_adb() {
  if [[ -n "${ADB_BIN}" ]]; then
    [[ -x "${ADB_BIN}" ]] || die "ADB_BIN 不可执行: ${ADB_BIN}"
    printf '%s' "${ADB_BIN}"
    return
  fi
  local candidate
  for candidate in \
    "$(command -v adb 2>/dev/null || true)" \
    "${ANDROID_HOME:-}/platform-tools/adb" \
    "${ANDROID_SDK_ROOT:-}/platform-tools/adb" \
    "${HOME}/Library/Android/sdk/platform-tools/adb"; do
    if [[ -n "${candidate}" && -x "${candidate}" ]]; then
      printf '%s' "${candidate}"
      return
    fi
  done
  return 1
}

ADB="$(resolve_adb || true)"
[[ -n "${ADB}" ]] || die "找不到 adb，可用 ADB_BIN=/path/to/adb 指定"

DEVICES="$("${ADB}" devices | tail -n +2 | awk 'NF >= 2 { print $1, $2 }')"
[[ -n "${DEVICES}" ]] || die "没有检测到设备。请手机开启开发者选项 > USB 调试（或无线调试），并确认 USB 已连接"

CHOSEN_SERIAL=""
CHOSEN_STATE=""
ONLINE_COUNT=0

while read -r serial state; do
  [[ -n "${serial}" ]] || continue
  if [[ "${state}" == "device" ]]; then
    ONLINE_COUNT=$(( ONLINE_COUNT + 1 ))
  fi
  if [[ -n "${SERIAL}" && "${serial}" == "${SERIAL}" ]]; then
    CHOSEN_SERIAL="${serial}"
    CHOSEN_STATE="${state}"
  fi
  if [[ -z "${SERIAL}" && -z "${CHOSEN_SERIAL}" && "${state}" == "device" ]]; then
    CHOSEN_SERIAL="${serial}"
    CHOSEN_STATE="${state}"
  fi
done <<< "${DEVICES}"

if [[ -n "${SERIAL}" && -z "${CHOSEN_SERIAL}" ]]; then
  printf '[deploy] 当前设备列表:\n%s\n' "${DEVICES}" >&2
  die "设备 ${SERIAL} 不在线"
fi

[[ -n "${CHOSEN_SERIAL}" ]] || {
  printf '[deploy] 当前设备列表:\n%s\n' "${DEVICES}" >&2
  die "没有处于在线状态（device）的设备，若是 unauthorized 请在手机上点「允许 USB 调试」"
}

if [[ -z "${SERIAL}" && "${ONLINE_COUNT}" -gt 1 ]]; then
  printf '[deploy] 当前设备列表:\n%s\n' "${DEVICES}" >&2
  die "检测到 ${ONLINE_COUNT} 台在线设备，请用 -s <序列号> 指定目标"
fi

[[ -z "${CHOSEN_STATE}" || "${CHOSEN_STATE}" == "device" ]] \
  || die "设备 ${CHOSEN_SERIAL} 状态为 ${CHOSEN_STATE}，请在手机上授权 USB 调试"

# ---------- APK ----------
if [[ -z "${APK}" ]]; then
  for candidate in "builds/android/gd-music-debug.apk" "builds/android/gd-music-release.apk"; do
    if [[ -f "${ROOT_DIR}/${candidate}" ]]; then
      APK="${ROOT_DIR}/${candidate}"
      break
    fi
  done
fi
[[ -n "${APK}" ]] || die "找不到 APK，请先运行 tools/package.sh，或用 -a 指定路径"
[[ "${APK}" = /* ]] || APK="${ROOT_DIR}/${APK}"
[[ -f "${APK}" ]] || die "APK 不存在: ${APK}"

# ---------- 包名 ----------
if [[ -z "${PACKAGE}" && -f "${ROOT_DIR}/export_presets.cfg" ]]; then
  PACKAGE="$(grep -m1 '^package/unique_name=' "${ROOT_DIR}/export_presets.cfg" | strip_ini_value || true)"
fi
[[ -n "${PACKAGE}" ]] || die "读不到包名，请用 -k 指定"

DEVICE_MODEL="$("${ADB}" -s "${CHOSEN_SERIAL}" shell getprop ro.product.model 2>/dev/null | tr -d '\r' || true)"

log "设备: ${CHOSEN_SERIAL}${DEVICE_MODEL:+ (${DEVICE_MODEL})}"
log "包名: ${PACKAGE}"
log "APK: ${APK#${ROOT_DIR}/} ($(du -h "${APK}" | cut -f1 | tr -d ' '))"

if [[ "${DO_UNINSTALL}" -eq 1 ]]; then
  log "卸载旧版本（应用数据会被清除）..."
  "${ADB}" -s "${CHOSEN_SERIAL}" uninstall "${PACKAGE}" >/dev/null 2>&1 || true
fi

log "安装中..."
if ! INSTALL_OUTPUT="$("${ADB}" -s "${CHOSEN_SERIAL}" install -r -d "${APK}" 2>&1)"; then
  printf '%s\n' "${INSTALL_OUTPUT}" >&2
  die "安装失败"
fi
printf '%s\n' "${INSTALL_OUTPUT}" | grep -q 'Success' || {
  printf '%s\n' "${INSTALL_OUTPUT}" >&2
  die "安装失败"
}
log "安装成功"

# ---------- 安装结果 ----------
"${ADB}" -s "${CHOSEN_SERIAL}" shell dumpsys package "${PACKAGE}" 2>/dev/null \
  | grep -E 'versionName|versionCode|lastUpdateTime' | head -n 3 | sed 's/^/           /' || true

if [[ -f "${ROOT_DIR}/build_info.cfg" ]]; then
  LOGGED_BUILD="$(grep -m1 '^number=' "${ROOT_DIR}/build_info.cfg" | cut -d= -f2- | tr -d '"\r' || true)"
  LOGGED_PLATFORM="$(grep -m1 '^platform=' "${ROOT_DIR}/build_info.cfg" | cut -d= -f2- | tr -d '"\r' || true)"
  log "最后一次打包: build=${LOGGED_BUILD} (${LOGGED_PLATFORM})"
fi

# ---------- 启动 ----------
if [[ "${DO_LAUNCH}" -eq 1 ]]; then
  log "启动应用..."
  if "${ADB}" -s "${CHOSEN_SERIAL}" shell monkey -p "${PACKAGE}" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; then
    log "已启动"
  else
    log "自动启动失败，请在手机上手动打开"
  fi
fi

# ---------- 日志 ----------
if [[ "${SHOW_LOG}" -eq 1 ]]; then
  log "最近的 Godot 日志:"
  sleep 2
  "${ADB}" -s "${CHOSEN_SERIAL}" logcat -d -t 600 -s godot:V AndroidRuntime:E 2>/dev/null \
    | tail -n 25 | sed 's/^/           /' || true
fi
