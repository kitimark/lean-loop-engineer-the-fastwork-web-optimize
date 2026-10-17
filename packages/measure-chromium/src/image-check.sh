#!/bin/sh
# Prints facts about the image: missing shared libraries, browser version, system fonts (must be none).
ldd /opt/hs/chrome-headless-shell | grep -i "not found" || echo "ldd: no missing libraries"
/opt/hs/chrome-headless-shell --version
echo "fc-list lines: $(fc-list | wc -l)"
echo "font-ish debian packages: $(dpkg -l | grep -i -c font)"
find / -xdev \( -name '*.ttf' -o -name '*.otf' -o -name '*.woff*' -o -name '*.pcf*' \) 2>/dev/null | head -3
