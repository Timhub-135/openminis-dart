#!/usr/bin/env python3
"""OpenMinis Share Reader — helper for the running agent.

Reads the single-conversation share buffer and returns, in a compact form,
any share blocks that have NOT been consumed yet (the agent marks them
consumed by deleting the file or via a cursor file).

Usage:
  python3 share_reader.py            # print all unconsumed shares as text
  python3 share_reader.py --consume  # print and mark them consumed
  python3 share_reader.py --cursor   # print current cursor (debug)

The buffer file is walked with a cursor: the offset of the byte where the
agent last stopped. New shares after that offset are offered.
"""
import argparse
import os
import sys

SHARE_FILE = "/root/services/share-receiver/data/incoming-share.txt"
CURSOR_FILE = "/root/services/share-receiver/data/incoming-share.txt.cursor"
SHARE_FILE = os.environ.get("SHARE_OUTPUT", SHARE_FILE)
CURSOR_FILE = os.environ.get("SHARE_CURSOR", SHARE_FILE + ".cursor")

# Separator line used by the receiver.
SEP = "---"


def _cursor():
    if not os.path.exists(CURSOR_FILE):
        return 0
    try:
        with open(CURSOR_FILE, "r", encoding="utf-8") as f:
            return int(f.read().strip() or "0")
    except (ValueError, OSError):
        return 0


def _set_cursor(pos):
    with open(CURSOR_FILE, "w", encoding="utf-8") as f:
        f.write(str(pos))


def read_shares(cursor: int):
    """Return (new_text, next_cursor). new_text is shares after byte-cursor."""
    if not os.path.exists(SHARE_FILE):
        return "", cursor
    # Cursor is a byte offset; track in bytes to stay aligned across reads.
    with open(SHARE_FILE, "rb") as f:
        f.seek(cursor)
        data_bytes = f.read()
    return data_bytes.decode("utf-8", errors="replace"), cursor + len(data_bytes)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--consume", action="store_true", help="mark shares consumed")
    ap.add_argument("--cursor", action="store_true", help="print cursor and exit")
    args = ap.parse_args()

    if args.cursor:
        print(_cursor())
        return

    cursor = _cursor()
    new_text, next_cursor = read_shares(cursor)
    if args.consume and new_text.strip():
        _set_cursor(next_cursor)

    if not new_text.strip():
        # Nothing new; print nothing (agent checks exit/detect emptiness).
        return
    print(new_text)


if __name__ == "__main__":
    main()
