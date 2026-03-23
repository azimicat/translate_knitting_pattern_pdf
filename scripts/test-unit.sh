#!/bin/bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

swift test 2>&1 | grep -E "(Test Case|passed|failed|Build complete|error:)"
