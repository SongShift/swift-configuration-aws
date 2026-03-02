#!/usr/bin/env bash

set -e

if ! command -v swiftformat &> /dev/null; then
    echo "Error: swiftformat is not installed."
    echo "Install via: brew install swiftformat"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$REPO_ROOT/.swiftformat"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found at $CONFIG_FILE"
    exit 1
fi

echo "Running swiftformat lint..."

swiftformat --lint --config "$CONFIG_FILE" "$REPO_ROOT"

echo "Lint complete!"
