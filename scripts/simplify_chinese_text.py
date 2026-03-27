#!/usr/bin/env python3

import sys


def main() -> int:
    try:
        from opencc import OpenCC
    except Exception as error:
        print(f"opencc import failed: {error}", file=sys.stderr)
        return 1

    text = sys.stdin.read()
    if not text:
        return 0

    converter = OpenCC("t2s")
    sys.stdout.write(converter.convert(text))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
