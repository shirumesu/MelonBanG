#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
dart_command=dart
if [ -n "${FLUTTER_ROOT:-}" ]; then
  dart_command="$FLUTTER_ROOT/bin/dart"
fi
exec "$dart_command" run scripts/flutter.dart "$@"
