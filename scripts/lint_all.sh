#!/usr/bin/env bash
# lint_all.sh — Run Verilator lint over all RTL modules
# Usage: bash scripts/lint_all.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RTL_DIRS=(core buffers framing arbitration adapters utils)
PASS=0; FAIL=0
for d in "${RTL_DIRS[@]}"; do
    for f in "$REPO_ROOT/rtl/$d"/*.sv; do
        [ -f "$f" ] || continue
        if verilator --lint-only --sv -Wall "$f" 2>/dev/null; then
            echo "PASS: $f"
            ((PASS++))
        else
            echo "FAIL: $f"
            ((FAIL++))
        fi
    done
done
echo ""
echo "Lint results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
