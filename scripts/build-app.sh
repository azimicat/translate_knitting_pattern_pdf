#!/bin/bash
set -eo pipefail

cd "$(dirname "$0")/.."

swift build 2>&1 | grep -E "(error:|Build complete|error\[)"
