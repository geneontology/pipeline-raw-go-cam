#!/usr/bin/env python3
"""Reduce a local copy of s3://go-data-product-live-go-cam/ttl/ to the
latest export's files.

The production export writes ttl/ with a non-deleting `aws s3 cp`, so the
prefix also holds models since removed from noctua-models; they stay until
the bucket's 30-day lifecycle expires them. The latest export is every
object written within WINDOW of the newest one (an export takes minutes).

Usage: select-latest-ttl-export.py LISTING MODELS_DIR
  LISTING     output of `aws s3api list-objects-v2 --prefix ttl/
              --query "Contents[].[Key,LastModified]" --output text`
  MODELS_DIR  local directory the prefix was copied into

Exits non-zero, changing nothing, if the latest export holds under
MIN_SHARE of the objects (a partial export) or if any of its files is
missing locally.
"""

import datetime
import os
import sys

WINDOW = datetime.timedelta(hours=3)
MIN_SHARE = 0.9


def main(listing, models_dir):
    written = {}
    with open(listing) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            key, last_modified = line.split("\t")
            name = key.rsplit("/", 1)[-1]
            if name.endswith(".ttl"):
                written[name] = datetime.datetime.fromisoformat(last_modified)
    if not written:
        sys.exit(f"no .ttl objects in {listing}")

    newest = max(written.values())
    latest = {n for n, t in written.items() if t >= newest - WINDOW}
    share = len(latest) / len(written)
    print(f"ttl/: {len(written)} objects; latest export ({newest:%Y-%m-%d %H:%M} UTC): "
          f"{len(latest)} ({share:.1%})")
    if share < MIN_SHARE:
        sys.exit(f"latest export holds only {share:.1%} of ttl/ (minimum {MIN_SHARE:.0%}); "
                 "refusing to continue on a possibly partial export")

    local = {n for n in os.listdir(models_dir) if n.endswith(".ttl")}
    missing = latest - local
    if missing:
        sys.exit(f"{len(missing)} files of the latest export are not in {models_dir}, "
                 f"e.g. {sorted(missing)[:5]}")

    stale = sorted(local - latest)
    for name in stale:
        os.remove(os.path.join(models_dir, name))
    print(f"removed {len(stale)} TTLs not in the latest export"
          + (f": {', '.join(stale[:20])}{' ...' if len(stale) > 20 else ''}" if stale else ""))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
