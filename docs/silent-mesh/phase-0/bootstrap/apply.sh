#!/usr/bin/env bash
# Apply the Silent Mesh bootstrap overlay onto a fresh fork clone.
# Usage: ./apply.sh /path/to/silent-mesh-fork-clone
set -euo pipefail

TARGET="${1:?usage: apply.sh /path/to/silent-mesh-fork-clone}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PLAN_DIR="$HERE/../.."   # docs/silent-mesh in the planning repo

[ -d "$TARGET/.git" ] || { echo "error: $TARGET is not a git clone" >&2; exit 1; }
[ -f "$TARGET/Cargo.toml" ] && grep -q 'buzz' "$TARGET/Cargo.toml" || {
  echo "error: $TARGET does not look like a buzz fork" >&2; exit 1; }

# Fork discipline + deploy profile
cp "$HERE/FORK.md" "$TARGET/FORK.md"
mkdir -p "$TARGET/deploy/silent-mesh"
cp "$HERE/deploy/silent-mesh/compose.silent-mesh.yml" \
   "$HERE/deploy/silent-mesh/README.md" \
   "$HERE/deploy/silent-mesh/.env.example" \
   "$TARGET/deploy/silent-mesh/"

# The plan becomes canonical in the fork
mkdir -p "$TARGET/docs/silent-mesh"
cp "$PLAN_DIR/architecture.md" "$PLAN_DIR/roadmap.md" "$TARGET/docs/silent-mesh/"

echo "Overlay applied. Review with: git -C $TARGET status"
echo "Then: git -C $TARGET add -A && git -C $TARGET commit -m 'silent-mesh: bootstrap overlay'"
