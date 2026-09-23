#!/bin/bash
# Superset workspace teardown: run when a workspace is deleted.
# Setup starts nothing persistent; the Run button may have started the
# app. Stop only instances whose executable lives inside this worktree,
# so an installed Deskjockey.app is never touched.
set -u

for name in Deskjockey DeskjockeyApp; do
    for pid in $(pgrep -x "$name" 2>/dev/null); do
        exe=$(ps -o comm= -p "$pid" 2>/dev/null)
        case "$exe" in
            "$PWD"/*)
                kill "$pid" 2>/dev/null && echo "Stopped $name (pid $pid, $exe)"
                ;;
        esac
    done
done

exit 0
