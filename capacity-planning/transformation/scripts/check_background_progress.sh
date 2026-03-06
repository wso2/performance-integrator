#!/bin/bash
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SELF_DIR/../../../scripts/check_background_progress.sh" --dir "$SELF_DIR" "$@"
