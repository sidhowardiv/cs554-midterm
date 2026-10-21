#!/bin/bash
set -euo pipefail
LIMA=${LIMA:-/opt/homebrew/bin/limactl}
exec "$LIMA" shell cs554-vm sudo k3s kubectl "$@"
