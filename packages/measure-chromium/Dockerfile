# Counts lane, Chromium arm (docs/plan/PLAN.md section 4.1-4.2).
# Linux arm64 container running Playwright's chromium-headless-shell (Chrome Headless Shell 156.0.8078.4 =
# playwright-core 1.64.1 "chromium-headless-shell v1248") with HeadlessExperimental BeginFrameControl.
# Chromium refuses BeginFrameControl on macOS (headless/lib/browser/protocol/target_handler.cc l.62-65 @317846d579b2),
# hence the container. The image holds NO system fonts: every font the page uses is served from the read-only
# snapshot mounted at /snapshot (fallback fonts would change line breaks, so layout and paint counts).
# Pinned: base image by digest (node:24-bookworm-slim, linux/arm64), every Debian package by version (dated
# snapshot.debian.org mirror + a manifest checked at build time), browser zip by sha256, npm packages by lock file.
FROM node:24-bookworm-slim@sha256:a5f4366e834695d5f363b920c104953a535d3a9864d1bdf74566a0ebe01daee5

ARG HS_VERSION=156.0.8078.4
ARG HS_SHA256=81ab9d4d3c301dc5fdfb6c541b9e6632b16fc819a6a854460f40a76fe2b2c476
ARG HS_URL=https://cdn.playwright.dev/builds/cft/${HS_VERSION}/linux-arm64/chrome-headless-shell-linux-arm64.zip

# Debian packages: every installed package is pinned. The mirror is a dated snapshot.debian.org archive (SNAP), the 29
# direct packages are installed as name=version taken from docker/apt-manifest.txt, and the build FAILS unless dpkg's full
# package list equals that manifest (regenerate it with `node src/pin-apt.mjs <image>` after a deliberate change).
# The list is the browser's own deb.deps minus fonts-liberation, wget and xdg-utils (no fonts, no helpers).
ARG SNAP=20261016T000000Z
COPY docker/apt-manifest.txt /tmp/apt-manifest.txt
RUN set -eux; \
    printf 'Types: deb\nURIs: http://snapshot.debian.org/archive/debian/%s/\nSuites: bookworm bookworm-updates\nComponents: main\nSigned-By: /usr/share/keyrings/debian-archive-keyring.gpg\n\nTypes: deb\nURIs: http://snapshot.debian.org/archive/debian-security/%s/\nSuites: bookworm-security\nComponents: main\nSigned-By: /usr/share/keyrings/debian-archive-keyring.gpg\n' "$SNAP" "$SNAP" > /etc/apt/sources.list.d/debian.sources; \
    printf 'Acquire::Retries "10";\nAcquire::Check-Valid-Until "false";\n' > /etc/apt/apt.conf.d/80snapshot; \
    apt-get update; \
    PINS=""; \
    for p in ca-certificates curl unzip fontconfig-config libfontconfig1 \
      libasound2 libatk-bridge2.0-0 libatk1.0-0 libatspi2.0-0 libcairo2 libcups2 libdbus-1-3 libexpat1 \
      libgbm1 libglib2.0-0 libgtk-3-0 libnspr4 libnss3 libpango-1.0-0 libudev1 libvulkan1 libx11-6 libxcb1 \
      libxcomposite1 libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2; do \
      PINS="$PINS $(grep "^$p=" /tmp/apt-manifest.txt)"; \
    done; \
    apt-get install -y --no-install-recommends $PINS; \
    dpkg --purge --force-depends $(dpkg-query -W -f='${Package}\n' 'fonts-*' 'ttf-*' 2>/dev/null) || true; \
    rm -rf /usr/share/fonts /var/lib/apt/lists/*; \
    test -z "$(find / -xdev \( -name '*.ttf' -o -name '*.otf' -o -name '*.pfb' -o -name '*.woff*' -o -name '*.pcf*' \) 2>/dev/null | head -1)"; \
    dpkg-query -W -f='${Package}=${Version}\n' | LC_ALL=C sort > /tmp/apt-now.txt; \
    diff /tmp/apt-now.txt /tmp/apt-manifest.txt

RUN set -eux; \
    curl -fsSL --retry 10 --retry-all-errors --retry-delay 3 -o /tmp/hs.zip "$HS_URL"; \
    echo "$HS_SHA256  /tmp/hs.zip" | sha256sum -c -; \
    mkdir -p /opt && unzip -q /tmp/hs.zip -d /opt && rm /tmp/hs.zip; \
    mv /opt/chrome-headless-shell-linux-arm64 /opt/hs; \
    chmod +x /opt/hs/chrome-headless-shell

# Fontconfig with no <dir>: the system font set is empty on purpose.
COPY docker/fonts.conf /etc/fonts/fw-empty-fonts.conf
ENV FONTCONFIG_FILE=/etc/fonts/fw-empty-fonts.conf

# npm: puppeteer-core and all its transitive packages, pinned by docker/driver/package-lock.json (npm ci).
WORKDIR /opt/driver
COPY docker/driver/package.json docker/driver/package-lock.json /opt/driver/
RUN npm ci --no-audit --no-fund --ignore-scripts

ENV FW_CHROME=/opt/hs/chrome-headless-shell
# The driver (src/) is mounted at /driver, the snapshot at /snapshot (read-only), outputs at /out.
# ESM resolution walks up from /driver/*.mjs and finds /node_modules (NODE_PATH is ignored by ESM).
RUN ln -s /opt/driver/node_modules /node_modules
ENTRYPOINT ["node", "/driver/run.mjs"]
