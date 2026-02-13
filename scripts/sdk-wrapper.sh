#!/bin/bash
# Installed as sdk/flutter/bin/flutter and sdk/flutter/bin/dart by `make setup-wrappers`.
# On the host: runs the command in the container, in the current directory, so flutter and dart
# behave as if installed locally. Inside the container (e.g. Gradle calling flutter.sdk/bin/flutter):
# runs the real SDK.
tool="$(basename "$0")"
[ -f /.dockerenv ] && exec "$(dirname "$0")/$tool.backup" "$@"

container=flutter-android-dev

# First line: running state, then one mount destination per line
info=$(docker inspect -f '{{.State.Running}}{{range .Mounts}}{{"\n"}}{{.Destination}}{{end}}' "$container" 2>/dev/null)
if [ -z "$info" ]; then
    echo "$tool: container $container does not exist, run 'make start' in flutter-docker" >&2
    exit 1
fi
if [ "${info%%$'\n'*}" != true ]; then
    docker start "$container" >/dev/null || exit 1
fi

# The current directory must be mounted in the container (at the same path)
mounted=
while read -r dest; do
    case "$PWD/" in "${dest%/}/"*) mounted=1; break ;; esac
done <<< "$(tail -n +2 <<< "$info")"
if [ -z "$mounted" ]; then
    echo "$tool: $PWD is not mounted in the container (only WORKSPACE_PATH is, see flutter-docker/.env)" >&2
    exit 1
fi

# Allocate a TTY only when attached to a terminal (keeps `flutter run` keys and colors working,
# and stdout clean for IDEs and pipes)
opts=(-i)
[ -t 0 ] && [ -t 1 ] && opts+=(-t -e "TERM=${TERM:-xterm}")

exec docker exec "${opts[@]}" -w "$PWD" "$container" "$tool" "$@"
