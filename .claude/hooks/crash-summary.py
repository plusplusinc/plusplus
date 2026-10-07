#!/usr/bin/env python3
"""Summarizes PlusPlus crash reports: time, simulator, exception, and the crashed thread's top
frames, one block per report. Other apps' reports are skipped.

    crash-summary.py <file.ips>...

An .ips file is a JSON header line followed by the JSON report.
"""

import json
import re
import sys

BUNDLE_ID = "com.plusplusinc.plusplus"
FRAMES = 8


def summarize(path):
    with open(path, encoding="utf-8") as file:
        header = json.loads(file.readline())
        if header.get("bundleID") != BUNDLE_ID:
            return None
        report = json.loads(file.read())
    simulator = re.search(r"/Devices/([0-9A-F-]{36})/", report.get("procPath", ""))
    exception = report.get("exception", {})
    termination = report.get("termination", {})
    lines = [
        f"{report.get('captureTime', header.get('timestamp', '?'))}"
        f"  simulator {simulator.group(1) if simulator else 'none (device or Mac)'}",
        f"  {exception.get('type', '?')} {exception.get('signal', '')}"
        f" {exception.get('subtype', '')} {termination.get('indicator', '')}".rstrip(),
    ]
    images = report.get("usedImages", [])
    crashed = next((t for t in report.get("threads", []) if t.get("triggered")), None)
    for frame in (crashed or {}).get("frames", [])[:FRAMES]:
        index = frame.get("imageIndex")
        image = images[index].get("name", "?") if index is not None and index < len(images) else "?"
        lines.append(f"    {image}  {frame.get('symbol', hex(frame.get('imageOffset', 0)))}")
    lines.append(f"  {path}")
    return "\n".join(lines)


def main():
    blocks = []
    for path in sys.argv[1:]:
        try:
            block = summarize(path)
        except (OSError, ValueError) as error:
            block = f"unreadable crash report {path}: {error}"
        if block:
            blocks.append(block)
    print("\n".join(blocks))


main()
