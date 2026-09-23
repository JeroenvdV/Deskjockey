#!/bin/bash
# Superset workspace setup: run in a fresh worktree on workspace creation.
set -euo pipefail

echo "==> Deskjockey workspace setup"

# 1. Resolve Swift package dependencies (the package currently has none,
#    so this is a no-op that stays correct if dependencies are added).
swift package resolve

# 2. Generate the Xcode project. It is gitignored, so a fresh worktree
#    does not have it. swift build / swift test do not need it, but
#    xcodebuild and app-bundle builds do.
if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate
else
    echo "Warning: xcodegen not found. Install it to build the .app: brew install xcodegen"
fi

# 3. Copy untracked local files from the main checkout into this worktree.
#    Add new file names to LOCAL_FILES as needed. Missing files are skipped.
LOCAL_FILES=(.env .env.local)
ROOT="${SUPERSET_ROOT_PATH:-}"
if [ -n "$ROOT" ] && [ "$ROOT" != "$PWD" ]; then
    for f in "${LOCAL_FILES[@]}"; do
        if [ -f "$ROOT/$f" ] && [ ! -e "$f" ]; then
            cp "$ROOT/$f" "$f"
            echo "Copied $f from $ROOT"
        fi
    done
fi

# 4. Warm the build so swift test and the Run button start fast.
swift build

echo "==> Setup complete"
