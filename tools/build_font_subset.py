#!/usr/bin/env python3
"""生成 Android 发布用中文字体子集。

完整版 `assets/fonts/NotoSansCJKsc-Medium.otf`（16.5 MB）不参与导出，
导出时使用本脚本产出的 `assets/fonts/NotoSansCJKsc-Medium-subset.otf`（约 4.4 MB）。

字符集由四部分叠加：
  1. ASCII + Latin-1（数字、英文、常见西文标点）
  2. GB2312 全集（大陆常用 6763 汉字 + 符号）
  3. Big5 常用字区（A440-C67E，繁体常用字，覆盖港台与日文汉字变体）
  4. 项目源码中实际出现过的所有非 ASCII 字符（.gd/.tscn/.tres/.csv/.json）
再补日文假名与全角标点。

依赖 fontTools（不进项目依赖，用临时虚拟环境）：

    python3 -m venv /tmp/fontsub && /tmp/fontsub/bin/pip install fonttools brotli
    /tmp/fontsub/bin/python tools/build_font_subset.py

改动源码文案、或发现某些字显示成方块后，重跑本脚本即可重新生成子集。
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "assets/fonts/NotoSansCJKsc-Medium.otf")
TARGET = os.path.join(ROOT, "assets/fonts/NotoSansCJKsc-Medium-subset.otf")

SCAN_EXT = {".gd", ".tscn", ".tres", ".csv", ".json"}
SKIP_DIRS = {
    ".git", ".godot", ".tools", "builds", "docs",
    "vendor", "thirdparty", "bin", "aar-build",
}


def project_chars() -> set[str]:
    """收集项目源码里出现过的非 ASCII 字符。"""
    found: set[str] = set()
    for root, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            if os.path.splitext(name)[1] not in SCAN_EXT:
                continue
            path = os.path.join(root, name)
            try:
                with open(path, encoding="utf-8", errors="ignore") as handle:
                    found |= {ch for ch in handle.read() if ord(ch) > 0x7F}
            except OSError:
                continue
    return found


def gb2312_chars() -> set[str]:
    chars: set[str] = set()
    for high in range(0xA1, 0xF8):
        for low in range(0xA1, 0xFF):
            try:
                chars.add(bytes([high, low]).decode("gb2312"))
            except UnicodeDecodeError:
                continue
    return chars


def big5_common_chars() -> set[str]:
    """Big5 常用字区（A440–C67E）。"""
    chars: set[str] = set()
    for high in range(0xA4, 0xC7):
        for low in range(0x40, 0xFF):
            if high > 0xC6 and low > 0x7E:
                continue
            try:
                char = bytes([high, low]).decode("big5")
            except UnicodeDecodeError:
                continue
            if len(char) == 1:
                chars.add(char)
    return chars


def build_charset() -> set[str]:
    charset = {chr(code) for code in range(0x20, 0x7F)}   # ASCII 可见字符
    charset |= {chr(code) for code in range(0xA0, 0x100)}  # Latin-1
    charset |= {chr(code) for code in range(0x3000, 0x3040)}  # CJK 标点
    charset |= {chr(code) for code in range(0x3041, 0x3100)}  # 平假名/片假名
    charset |= gb2312_chars()
    charset |= big5_common_chars()
    charset |= project_chars()
    return charset


def main() -> int:
    if not os.path.isfile(SOURCE):
        print(f"找不到源字体: {SOURCE}", file=sys.stderr)
        return 1

    charset = build_charset()
    print(f"字符集大小: {len(charset)}")

    with tempfile.NamedTemporaryFile("w", suffix=".txt", encoding="utf-8", delete=False) as handle:
        handle.write("".join(sorted(charset)))
        text_path = handle.name
    try:
        subprocess.run(
            [
                sys.executable, "-m", "fontTools.subset", SOURCE,
                f"--text-file={text_path}",
                f"--output-file={TARGET}",
                "--layout-features=*",
                "--no-hinting",
                "--desubroutinize",
                "--drop-tables+=DSIG",
                "--name-IDs=*",
            ],
            check=True,
        )
    finally:
        os.unlink(text_path)

    size_mb = os.path.getsize(TARGET) / (1024 * 1024)
    src_mb = os.path.getsize(SOURCE) / (1024 * 1024)
    print(f"已生成 {TARGET}")
    print(f"{src_mb:.2f} MB → {size_mb:.2f} MB（省 {src_mb - size_mb:.2f} MB）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
