#!/usr/bin/env bash
set -euo pipefail

# 打包脚本：调用 Godot headless 按 export_presets.cfg 导出安装包。
# 构建号由 addons/dx_build_number 在导出时自动 +1 并写回 build_info.cfg。

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GODOT_BIN="${GODOT_BIN:-}"
PLATFORM="android"
MODE="debug"
OUTPUT=""
LOG_FILE=""
CHECK_ONLY=0

usage() {
  cat <<'EOF'
用法: tools/package.sh [选项]

选项:
  -p, --platform <android|windows>  导出平台，默认 android
  -m, --mode <debug|release>        构建类型，默认 debug
  -o, --output <path>               覆盖输出路径（相对项目根目录）
  -c, --check                       只检查环境（Godot/模板/SDK/JDK），不导出
  -h, --help                        显示帮助

环境变量:
  GODOT_BIN      Godot 可执行文件路径，默认自动探测
  ANDROID_HOME   Android SDK 路径（导出 Android 时使用）
  JAVA_HOME      JDK 路径（导出 Android 时使用）

示例:
  tools/package.sh                          # Android debug
  tools/package.sh -m release               # Android release（需先配置签名）
  tools/package.sh -p windows -m release    # Windows release
EOF
}

log() { printf '[package] %s\n' "$*"; }

# 解析 cfg/ini 里的 key=value 或 key = value，去掉两侧引号
strip_ini_value() {
  sed -e 's/^[^=]*=[[:space:]]*//' -e 's/^"//' -e 's/"[[:space:]]*$//'
}
die() {
  printf '[package] 错误: %s\n' "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--platform)
      [[ $# -ge 2 ]] || die "$1 需要一个参数"
      PLATFORM="$2"
      shift 2
      ;;
    -m|--mode)
      [[ $# -ge 2 ]] || die "$1 需要一个参数"
      MODE="$2"
      shift 2
      ;;
    -o|--output)
      [[ $# -ge 2 ]] || die "$1 需要一个参数"
      OUTPUT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -c|--check)
      CHECK_ONLY=1
      shift
      ;;
    *)
      die "未知参数: $1（用 -h 查看用法）"
      ;;
  esac
done

case "${PLATFORM}" in
  android) PRESET="Android" ;;
  windows) PRESET="Windows Desktop" ;;
  *) die "不支持的平台: ${PLATFORM}（可选 android / windows）" ;;
esac

case "${MODE}" in
  debug|release) ;;
  *) die "不支持的构建类型: ${MODE}（可选 debug / release）" ;;
esac

[[ -f "${ROOT_DIR}/project.godot" ]] || die "找不到 ${ROOT_DIR}/project.godot"
[[ -f "${ROOT_DIR}/export_presets.cfg" ]] || die "找不到 export_presets.cfg"

# ---------- 定位 Godot ----------
resolve_godot() {
  if [[ -n "${GODOT_BIN}" ]]; then
    [[ -x "${GODOT_BIN}" ]] || die "GODOT_BIN 不可执行: ${GODOT_BIN}"
    printf '%s' "${GODOT_BIN}"
    return
  fi
  local candidate
  for candidate in \
    "/Applications/Godot.app/Contents/MacOS/Godot" \
    "$(command -v godot 2>/dev/null || true)" \
    "$(command -v godot4 2>/dev/null || true)"; do
    if [[ -n "${candidate}" && -x "${candidate}" ]]; then
      printf '%s' "${candidate}"
      return
    fi
  done
  return 1
}

GODOT="$(resolve_godot || true)"
[[ -n "${GODOT}" ]] || die "找不到 Godot，可用 GODOT_BIN=/path/to/Godot 指定"

GODOT_VERSION="$("${GODOT}" --version 2>/dev/null | head -n 1 | tr -d '\r' || true)"
[[ -n "${GODOT_VERSION}" ]] || die "无法读取 Godot 版本: ${GODOT}"
# 导出模板目录名形如 4.7.stable（去掉 .official.<hash>）
TEMPLATE_VERSION="${GODOT_VERSION%%.official*}"

# ---------- 用户数据目录（编辑器设置 / 导出模板） ----------
godot_user_data_dirs() {
  printf '%s\n' "${HOME}/Library/Application Support/Godot"
  printf '%s\n' "${XDG_DATA_HOME:-${HOME}/.local/share}/godot"
  printf '%s\n' "${XDG_CONFIG_HOME:-${HOME}/.config}/godot"
}

latest_editor_settings() {
  local dir file mtime best="" best_mtime=0
  while IFS= read -r dir; do
    [[ -d "${dir}" ]] || continue
    for file in "${dir}"/editor_settings-*.tres; do
      [[ -f "${file}" ]] || continue
      mtime="$(stat -f %m "${file}" 2>/dev/null || stat -c %Y "${file}" 2>/dev/null || echo 0)"
      if [[ "${mtime}" -gt "${best_mtime}" ]]; then
        best_mtime="${mtime}"
        best="${file}"
      fi
    done
  done < <(godot_user_data_dirs)
  printf '%s' "${best}"
}

setting_of() {
  local file="$1" key="$2"
  [[ -n "${file}" && -f "${file}" ]] || return 0
  grep -m1 "^${key}[[:space:]]*=" "${file}" 2>/dev/null | strip_ini_value || true
}

EDITOR_SETTINGS="$(latest_editor_settings)"

find_templates_dir() {
  local base
  while IFS= read -r base; do
    if [[ -d "${base}/export_templates/${TEMPLATE_VERSION}" ]]; then
      printf '%s' "${base}/export_templates/${TEMPLATE_VERSION}"
      return 0
    fi
  done < <(godot_user_data_dirs)
  return 1
}

TEMPLATES_DIR="$(find_templates_dir || true)"
if [[ -z "${TEMPLATES_DIR}" ]]; then
  die "找不到 ${TEMPLATE_VERSION} 的导出模板。请在编辑器里 编辑器 > 管理导出模板 安装（当前 Godot 版本: ${GODOT_VERSION}）"
fi
log "Godot: ${GODOT}"
log "版本: ${GODOT_VERSION}"
log "导出模板: ${TEMPLATES_DIR}"

# ---------- 检查导出预设与模板文件 ----------
grep -q "^platform=\"${PRESET}\"$" "${ROOT_DIR}/export_presets.cfg" \
  || die "export_presets.cfg 里没有 ${PRESET} 预设"

case "${PLATFORM}:${MODE}" in
  android:debug)   TEMPLATE_FILE="android_debug.apk" ;;
  android:release) TEMPLATE_FILE="android_release.apk" ;;
  windows:debug)   TEMPLATE_FILE="windows_debug_x86_64.exe" ;;
  windows:release) TEMPLATE_FILE="windows_release_x86_64.exe" ;;
esac
[[ -f "${TEMPLATES_DIR}/${TEMPLATE_FILE}" ]] \
  || die "导出模板缺少 ${TEMPLATE_FILE}，请重新安装 ${TEMPLATE_VERSION} 的导出模板"

# ---------- Android 环境检查 ----------
if [[ "${PLATFORM}" == "android" ]]; then
  ANDROID_SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  if [[ -z "${ANDROID_SDK}" ]]; then
    ANDROID_SDK="$(setting_of "${EDITOR_SETTINGS}" "export/android/android_sdk_path")"
  fi
  if [[ -z "${ANDROID_SDK}" && -d "${HOME}/Library/Android/sdk" ]]; then
    ANDROID_SDK="${HOME}/Library/Android/sdk"
  fi
  [[ -n "${ANDROID_SDK}" && -d "${ANDROID_SDK}" ]] \
    || die "找不到 Android SDK，请设置 ANDROID_HOME 或在 Godot 编辑器设置里配置 android_sdk_path"
  [[ -d "${ANDROID_SDK}/platforms" ]] || die "Android SDK 缺少 platforms 目录: ${ANDROID_SDK}"
  [[ -d "${ANDROID_SDK}/build-tools" ]] || die "Android SDK 缺少 build-tools 目录: ${ANDROID_SDK}"
  export ANDROID_HOME="${ANDROID_SDK}"
  export ANDROID_SDK_ROOT="${ANDROID_SDK}"

  JDK_PATH="${JAVA_HOME:-}"
  if [[ -z "${JDK_PATH}" ]]; then
    JDK_PATH="$(setting_of "${EDITOR_SETTINGS}" "export/android/java_sdk_path")"
  fi
  if [[ -z "${JDK_PATH}" && -x /usr/libexec/java_home ]]; then
    JDK_PATH="$(/usr/libexec/java_home 2>/dev/null || true)"
  fi
  [[ -n "${JDK_PATH}" && -x "${JDK_PATH}/bin/java" ]] \
    || die "找不到可用的 JDK（Godot 4.7 要求 JDK 17 及以上），请设置 JAVA_HOME"
  export JAVA_HOME="${JDK_PATH}"

  if [[ "${MODE}" == "debug" ]]; then
    DEBUG_KEYSTORE="$(setting_of "${EDITOR_SETTINGS}" "export/android/debug_keystore")"
    [[ -n "${DEBUG_KEYSTORE}" ]] || DEBUG_KEYSTORE="${HOME}/.android/debug.keystore"
    if [[ ! -f "${DEBUG_KEYSTORE}" ]]; then
      log "调试签名文件不存在（${DEBUG_KEYSTORE}），Godot 会尝试自动生成"
    fi
  else
    PRESET_RELEASE_KEYSTORE="$(grep -m1 '^keystore/release=' "${ROOT_DIR}/export_presets.cfg" | strip_ini_value || true)"
    RELEASE_KEYSTORE="${PRESET_RELEASE_KEYSTORE:-$(setting_of "${EDITOR_SETTINGS}" "export/android/release_keystore")}"
    [[ -n "${RELEASE_KEYSTORE}" ]] \
      || die "release 包未配置签名：请在 项目 > 导出 > Android > 密钥库 填写 release keystore、别名与密码"
  fi

  log "Android SDK: ${ANDROID_SDK}"
  log "JDK: ${JDK_PATH}"
fi

if [[ "${CHECK_ONLY}" -eq 1 ]]; then
  log "环境检查通过（${PLATFORM} / ${MODE}）"
  exit 0
fi

# ---------- 输出路径 ----------
case "${PLATFORM}:${MODE}" in
  android:debug)   DEFAULT_OUTPUT="builds/android/gd-music-debug.apk" ;;
  android:release) DEFAULT_OUTPUT="builds/android/gd-music-release.apk" ;;
  windows:debug)   DEFAULT_OUTPUT="builds/windows/gd-music-debug.exe" ;;
  windows:release) DEFAULT_OUTPUT="builds/windows/gd-music.exe" ;;
esac
[[ -n "${OUTPUT}" ]] || OUTPUT="${DEFAULT_OUTPUT}"
[[ "${OUTPUT}" = /* ]] || OUTPUT="${ROOT_DIR}/${OUTPUT}"

mkdir -p "$(dirname "${OUTPUT}")"
LOG_DIR="${ROOT_DIR}/builds/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/package-${PLATFORM}-${MODE}-$(date +%Y%m%d-%H%M%S).log"

read_build_info() {
  local key="$1"
  grep -m1 "^${key}=" "${ROOT_DIR}/build_info.cfg" 2>/dev/null | cut -d= -f2- | tr -d '"' || true
}

BUILD_NUMBER_BEFORE="$(read_build_info number)"

log "平台: ${PLATFORM}(${PRESET})  类型: ${MODE}"
log "构建号: ${BUILD_NUMBER_BEFORE:-0} -> $(( ${BUILD_NUMBER_BEFORE:-0} + 1 ))"
log "输出: ${OUTPUT#$ROOT_DIR/}"
log "日志: ${LOG_FILE#$ROOT_DIR/}"
if [[ "${PLATFORM}" == "android" ]]; then
  log "开始导出（Android 走 gradle，首次或模板变更时可能需要几分钟）..."
else
  log "开始导出..."
fi

START_SECONDS="$(date +%s)"
if ! "${GODOT}" --headless --path "${ROOT_DIR}" "--export-${MODE}" "${PRESET}" "${OUTPUT}" >"${LOG_FILE}" 2>&1; then
  printf '\n[package] 导出失败，日志尾部:\n' >&2
  tail -n 60 "${LOG_FILE}" >&2
  printf '\n[package] 完整日志: %s\n' "${LOG_FILE}" >&2
  exit 1
fi
ELAPSED_SECONDS=$(( $(date +%s) - START_SECONDS ))

[[ -f "${OUTPUT}" ]] || {
  tail -n 40 "${LOG_FILE}" >&2
  die "导出命令返回 0 但没有生成文件: ${OUTPUT}"
}

SIZE_BYTES="$(wc -c <"${OUTPUT}" | tr -d ' ')"
SIZE_HUMAN="$(du -h "${OUTPUT}" | cut -f1 | tr -d ' ')"
SHA256="$(shasum -a 256 "${OUTPUT}" | cut -d' ' -f1)"
BUILD_NUMBER_AFTER="$(read_build_info number)"

printf '\n'
log "导出完成（耗时 ${ELAPSED_SECONDS}s）"
log "产物: ${OUTPUT#$ROOT_DIR/}"
log "大小: ${SIZE_HUMAN} (${SIZE_BYTES} bytes)"
log "sha256: ${SHA256}"
log "构建号: ${BUILD_NUMBER_BEFORE:-0} -> ${BUILD_NUMBER_AFTER:-?}"
log "build_info: platform=$(read_build_info platform) debug=$(read_build_info debug)"

if [[ "${PLATFORM}" == "android" ]]; then
  log "下一步: tools/deploy_device.sh 安装到当前设备"
else
  log "Windows 包需在 Windows 上运行: ${OUTPUT#$ROOT_DIR/}"
fi
