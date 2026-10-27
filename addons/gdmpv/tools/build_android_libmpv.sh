#!/usr/bin/env bash
# 交叉编译 Android 版 libmpv（供 addons/gdmpv 的 GDExtension 链接与分发）。
#
# 用法：
#   ./tools/build_android_libmpv.sh arm64
#
# 产物分两处：
#   1. thirdparty/mpv-android/{include,lib/<arch>}/   —— 链接用（头文件 + libmpv.so）
#   2. bin/android_<arch>/*.so                        —— 分发用（strip 后的 libmpv、
#                                                        ffmpeg 运行时依赖、libc++_shared.so）
#
# 上游 mpv-android 的构建树（源码 + SDK/NDK + 中间产物，约 6 GB / 6 万文件）
# 默认落在 $HOME/.cache/gdmpv-build/mpv-android，**不要**放进项目目录：
# Godot 会扫描项目下所有文件，6 万文件的构建树会让编辑器与导出卡死。
# 可用 GDMPV_MPV_ANDROID_DIR 覆盖。
set -euo pipefail

ARCH="${1:-arm64}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDON_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORK="${GDMPV_MPV_ANDROID_DIR:-${HOME}/.cache/gdmpv-build/mpv-android}"
OUT="${MPV_ANDROID_PREFIX:-${ADDON_DIR}/thirdparty/mpv-android}"

case "${ARCH}" in
arm64 | armv7l | x86 | x86_64) ;;
*)
	echo "[gdmpv] 不支持的架构：${ARCH}（可选 arm64 / armv7l / x86 / x86_64）" >&2
	exit 1
	;;
esac

# buildall.sh 用了 declare -g，macOS 自带的 bash 3.2 不支持，会报
#   declare: -g: invalid option
# 所以优先用 brew 的 bash 5。
BASH_BIN=""
if [[ -x /opt/homebrew/bin/bash ]]; then
	BASH_BIN=/opt/homebrew/bin/bash
elif [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
	BASH_BIN="$(command -v bash)"
else
	echo "[gdmpv] 需要 bash 4+（buildall.sh 用了 declare -g）" >&2
	echo "[gdmpv]   brew install bash" >&2
	exit 1
fi

if [[ ! -d "${WORK}/buildscripts" ]]; then
	echo "[gdmpv] 拉取 mpv-android 构建脚本到 ${WORK}"
	mkdir -p "$(dirname "${WORK}")"
	git clone --depth 1 https://github.com/mpv-android/mpv-android.git "${WORK}"
fi

cd "${WORK}/buildscripts"

# download.sh 负责装 SDK/NDK 并拉 ffmpeg、mpv 等源码（首次数 GB）。
echo "[gdmpv] 准备依赖（download.sh）"
./download.sh

echo "[gdmpv] 编译 mpv（--arch ${ARCH}）"
"${BASH_BIN}" ./buildall.sh --arch "${ARCH}" mpv

PREFIX="${WORK}/buildscripts/prefix/${ARCH}"
if [[ ! -f "${PREFIX}/lib/libmpv.so" ]]; then
	echo "[gdmpv] 未找到 ${PREFIX}/lib/libmpv.so" >&2
	echo "[gdmpv] 请检查 buildall.sh 输出，确认 mpv 组件是否编译成功" >&2
	exit 1
fi

# --- 链接用产物：头文件 + 未 strip 的 libmpv.so ---
echo "[gdmpv] 整理链接产物到 ${OUT}"
mkdir -p "${OUT}/lib/${ARCH}" "${OUT}/include"
cp -f "${PREFIX}/lib/libmpv.so" "${OUT}/lib/${ARCH}/"
if [[ -d "${PREFIX}/include/mpv" ]]; then
	cp -Rf "${PREFIX}/include/mpv" "${OUT}/include/"
elif [[ -d "${WORK}/mpv/include/mpv" ]]; then
	cp -Rf "${WORK}/mpv/include/mpv" "${OUT}/include/"
else
	echo "[gdmpv] 未找到 mpv 头文件，请手工从 mpv 源码复制 include/mpv 到 ${OUT}/include/" >&2
	exit 1
fi

# --- 分发用产物：strip 后的运行时依赖 ---
# libmpv.so 是动态链接的，NEEDED 里带 libav*.so 与 libc++_shared.so，
# 这些必须和 GDExtension 一起打进 APK 的 lib/<abi>/。
NDK_DIR="$(echo "${WORK}"/buildscripts/sdk/android-ndk-*/)"
STRIP="$(echo "${NDK_DIR}"toolchains/llvm/prebuilt/*/bin/llvm-strip)"
case "${ARCH}" in
arm64) TRIPLE=aarch64-linux-android ;;
armv7l) TRIPLE=armv7a-linux-androideabi ;;
x86) TRIPLE=i686-linux-android ;;
x86_64) TRIPLE=x86_64-linux-android ;;
esac
BIN_OUT="${ADDON_DIR}/bin/android_${ARCH}"
mkdir -p "${BIN_OUT}"

for f in libmpv.so libavcodec.so libavdevice.so libavfilter.so \
	libavformat.so libavutil.so libswresample.so libswscale.so; do
	if [[ -f "${PREFIX}/lib/${f}" ]]; then
		cp -f "${PREFIX}/lib/${f}" "${BIN_OUT}/${f}"
		chmod u+w "${BIN_OUT}/${f}"
		"${STRIP}" --strip-unneeded "${BIN_OUT}/${f}" 2>/dev/null || true
	fi
done

LIBCXX="$(echo "${NDK_DIR}"toolchains/llvm/prebuilt/*/sysroot/usr/lib/"${TRIPLE}"/libc++_shared.so)"
if [[ -f "${LIBCXX}" ]]; then
	cp -f "${LIBCXX}" "${BIN_OUT}/libc++_shared.so"
else
	echo "[gdmpv] 未找到 libc++_shared.so：${LIBCXX}" >&2
fi

echo "[gdmpv] 分发产物：${BIN_OUT}"
ls -la "${BIN_OUT}"

echo "[gdmpv] 完成。现在可以编译 GDExtension："
echo "        cd ${ADDON_DIR}"
echo "        ANDROID_HOME=\"${WORK}/buildscripts/sdk/android-sdk-mac\" \\"
echo "        MPV_ANDROID_PREFIX=\"${OUT}\" \\"
echo "        scons platform=android target=template_debug arch=${ARCH} api_version=4.7 \\"
echo "              ndk_version=30.0.16248370 -j8"
