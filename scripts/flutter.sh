#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
case "${1:-}" in
  run|build) ;;
  *) echo 'Usage: ./scripts/flutter.sh run|build [Flutter arguments]' >&2; exit 2 ;;
esac

configuration_file=${MELONBANG_CONFIGURATION_FILE:-.env.service.json}
if [ ! -f "$configuration_file" ]; then
  echo 'Copy .env.service.example.json to .env.service.json and fill the service registrations first.' >&2
  exit 1
fi
flutter_command=flutter
if [ -n "${FLUTTER_ROOT:-}" ]; then
  flutter_command="$FLUTTER_ROOT/bin/flutter"
fi
exec "$flutter_command" "$@" "--dart-define-from-file=$configuration_file"
