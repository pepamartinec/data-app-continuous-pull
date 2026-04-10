#!/bin/bash
set -euo pipefail

WATCHED_DIR=/app/watched

echo "Running watched app setup..."
cd "$WATCHED_DIR"

if [ -f keboola-config/setup.sh ]; then
    bash keboola-config/setup.sh
else
    echo "Warning: no keboola-config/setup.sh found in watched repo"
fi

echo "Build complete."
