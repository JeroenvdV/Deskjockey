#!/bin/bash
# Superset Run button: build and launch the app from this worktree.
# Runs in the workspace's run pane; the app is a child of this process,
# so the pane's stop control quits it.
set -euo pipefail

# The app holds a machine-wide single-instance lock (/tmp/ai.mistral.Deskjockey.lock).
# If any Deskjockey is already running, this instance tells it to show its
# menu and exits. Stop the other instance first if that is not what you want.
swift run DeskjockeyApp
