#!/bin/sh
ldd /opt/hs/chrome-headless-shell | grep -i "not found" || echo "ldd: no missing libraries"
/opt/hs/chrome-headless-shell --version
echo "fc-list lines: $(fc-list | wc -l); families: $(fc-list : family | sort -u | tr '\n' ';')"
echo "font-ish debian packages: $(dpkg -l | grep -i -c font)"
find / -xdev \( -name '*.ttf' -o -name '*.otf' -o -name '*.woff*' -o -name '*.pcf*' \) 2>/dev/null | head -3
