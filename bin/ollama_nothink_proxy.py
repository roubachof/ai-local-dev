#!/usr/bin/env python3
from __future__ import annotations

import sys

from nothink_proxy import main


if __name__ == "__main__":
    raise SystemExit(main(["--mode", "ollama", *sys.argv[1:]]))
