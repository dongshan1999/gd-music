#!/usr/bin/env bash
set -euo pipefail

# Build the official EIRTeam.FFmpeg binaries for the platforms exported by this
# project. Run from the repository root on a macOS/Linux machine with SCons,
# FFmpeg build tools, and the Android SDK/NDK installed.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${EIRTEAM_FFMPEG_SOURCE:-${HOME}/Downloads/EIRTeam.FFmpeg-master}"
ANDROID_NDK_VERSION="${ANDROID_NDK_VERSION:-28.2.13676358}"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-${HOME}/Library/Android/sdk}}"
ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT:-${ANDROID_SDK_ROOT}/ndk/${ANDROID_NDK_VERSION}}"

if [[ ! -x "${ANDROID_NDK_ROOT}/ndk-build" ]]; then
  echo "Android NDK not found: ${ANDROID_NDK_ROOT}" >&2
  exit 1
fi
export ANDROID_SDK_ROOT ANDROID_NDK_ROOT

if [[ ! -d "${SOURCE_DIR}/.git" ]]; then
  echo "EIRTeam.FFmpeg source repository not found: ${SOURCE_DIR}" >&2
  echo "Set EIRTEAM_FFMPEG_SOURCE to an initialized checkout." >&2
  exit 1
fi

cd "${SOURCE_DIR}"
git submodule update --init --recursive
make gdextension PLATFORM=macos TARGET_ARCH=arm64

# Android playback only needs FFmpeg's decoders. Avoid the optional encoder
# dependencies (x264/x265/lame/libiconv) so the build works with a stock NDK.
PATH="${PATH}:/tmp/eirteam-tools" ./ffmpeg-kit/android.sh \
  --disable-arm-v7a --disable-arm-v7a-neon --disable-x86 --disable-x86-64 \
  --enable-android-media-codec --enable-android-zlib --no-archive
mkdir -p thirdparty/ffmpeg/android/arm64/lib thirdparty/ffmpeg/android/arm64/include
cp -R ffmpeg-kit/prebuilt/android-arm64/ffmpeg/include/. thirdparty/ffmpeg/android/arm64/include/
for lib in avcodec avfilter avformat avutil swresample swscale; do
  cp "ffmpeg-kit/prebuilt/android-arm64/ffmpeg/lib/lib${lib}.so" thirdparty/ffmpeg/android/arm64/lib/
done
if [[ ! -e "${ANDROID_SDK_ROOT}/ndk/23.2.8568313" ]]; then
  ln -s "${ANDROID_NDK_ROOT}" "${ANDROID_SDK_ROOT}/ndk/23.2.8568313"
fi
for target in template_debug template_release; do
  ANDROID_HOME="${ANDROID_SDK_ROOT}" scons -C gdextension_build platform=android arch=arm64 target="${target}" ffmpeg_path=../thirdparty/ffmpeg/android/arm64
done

mkdir -p "${ROOT_DIR}/addons/ffmpeg"
cp -R "${SOURCE_DIR}/gdextension_build/build/addons/ffmpeg/." "${ROOT_DIR}/addons/ffmpeg/"
echo "EIRTeam.FFmpeg binaries copied to ${ROOT_DIR}/addons/ffmpeg"
