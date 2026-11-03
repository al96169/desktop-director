#!/bin/bash
echo "CLT_PATH:"; xcode-select -p 2>&1
echo "SWIFT:"; swift --version 2>&1 | head -3
echo "PYTHON:"; /usr/bin/python3 -c 'import sys; print(sys.version)' 2>&1
echo "PYOBJC:"; /usr/bin/python3 -c 'import Quartz; print("pyobjc OK")' 2>&1 | head -2
echo "BREW:"; command -v brew || echo "no brew"
echo "AX_OSASCRIPT:"; osascript -e 'tell application "System Events" to get name of every process' 2>&1 | head -c 300
echo ""
echo "AX_WINDOWS:"; osascript -e 'tell application "System Events" to count windows of every process' 2>&1 | head -c 200
echo ""
echo "SCREENCAP_TRY:"; screencapture -x /tmp/ddir_probe.png 2>&1; ls -la /tmp/ddir_probe.png 2>&1
echo "DISPLAYS:"; system_profiler SPDisplaysDataType 2>/dev/null | sed -n '1,50p'
echo "APPS:"; osascript -e 'tell application "System Events" to get name of every application process whose visible is true' 2>&1 | head -c 300
echo ""
