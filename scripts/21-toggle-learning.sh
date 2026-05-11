#!/usr/bin/env bash
# Flip every association back to Learning.
set -eu
set -o pipefail || true
TARGET_MODE=Learning exec "$(dirname "$0")/20-toggle-enforced.sh"
