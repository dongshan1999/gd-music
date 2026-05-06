from __future__ import annotations

import argparse
from pathlib import Path
import sys


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Print a UTF-8 text file without mojibake."
    )
    parser.add_argument("path", help="File to display.")
    parser.add_argument(
        "--contains",
        dest="contains",
        default="",
        help="Only print lines containing this substring.",
    )
    parser.add_argument(
        "--start",
        type=int,
        default=1,
        help="1-based start line. Defaults to 1.",
    )
    parser.add_argument(
        "--end",
        type=int,
        default=0,
        help="1-based end line, inclusive. Defaults to EOF.",
    )
    parser.add_argument(
        "--line-numbers",
        action="store_true",
        help="Prefix each printed line with its line number.",
    )
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    target = Path(args.path).expanduser()
    if not target.is_absolute():
        target = (Path.cwd() / target).resolve()

    if not target.exists():
        print(f"File not found: {target}", file=sys.stderr)
        return 1
    if not target.is_file():
        print(f"Not a file: {target}", file=sys.stderr)
        return 1

    start_line = max(args.start, 1)
    end_line = args.end if args.end > 0 else sys.maxsize

    with target.open("r", encoding="utf-8", newline="") as handle:
        for index, line in enumerate(handle, start=1):
            if index < start_line:
                continue
            if index > end_line:
                break

            line_text = line.rstrip("\r\n")
            if args.contains and args.contains not in line_text:
                continue

            if args.line_numbers:
                print(f"{index}: {line_text}")
            else:
                print(line_text)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
