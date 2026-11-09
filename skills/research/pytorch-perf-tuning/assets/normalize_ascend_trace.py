#!/usr/bin/env python3
"""Normalize one Ascend timeline: input.json output.perfetto.json (times in us)."""

import argparse
import json
from decimal import Decimal
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    with args.source.open(encoding="utf-8") as stream:
        payload = json.load(stream, parse_float=Decimal)
    events = payload if isinstance(payload, list) else payload["traceEvents"]
    origin = min(Decimal(str(event["ts"])) for event in events
                 if "ts" in event and event.get("ph") != "M")
    flow_ids = {}
    for event in events:
        if "ts" in event:
            ts = Decimal(str(event["ts"]))
            event["ts"] = float(ts if event.get("ph") == "M" and ts == 0
                                else ts - origin)
        if event.get("ph") in ("s", "t", "f"):
            if "id2" in event:
                raise ValueError("id2 flow requires a separate format adapter")
            key = (event.get("cat", ""), event.get("scope", ""),
                   str(event["id"]))
            event["id"] = flow_ids.setdefault(key, len(flow_ids) + 1)

    if isinstance(payload, list):
        payload = {"traceEvents": events}
    previous_origin = Decimal(str(payload.get("ascendTimestampOriginUs", 0)))
    payload["ascendTimestampOriginUs"] = str(previous_origin + origin)
    with args.output.open("x", encoding="utf-8") as stream:
        json.dump(payload, stream, default=float, allow_nan=False,
                  ensure_ascii=False, separators=(",", ":"))
    print(f"events={len(events)}, flow_ids={len(flow_ids)}, output={args.output}")


if __name__ == "__main__":
    main()
