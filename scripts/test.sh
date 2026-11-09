#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Standalone Command Line Tools ship Testing.framework outside the default
# framework search path. Full Xcode configures its test runtime automatically.
DEVELOPER_DIR_PATH="$(xcode-select -p)"
if [[ "$DEVELOPER_DIR_PATH" == */CommandLineTools ]]; then
  FRAMEWORKS="$DEVELOPER_DIR_PATH/Library/Developer/Frameworks"
  swift test -Xswiftc -F -Xswiftc "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$FRAMEWORKS"
else
  swift test
fi
