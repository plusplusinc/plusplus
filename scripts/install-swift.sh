#!/usr/bin/env bash
# Install a Linux Swift toolchain inside a Claude Code cloud session so the
# Linux-testable suites (PlusPlusKit, PlusPlusCLI incl. DocsConformanceTests)
# run locally before a push instead of round-tripping through macOS CI.
#
# Verified 2026-07-10: download.swift.org is reachable through the session
# proxy and the toolchain runs on the Ubuntu 24.04 containers with no extra
# system packages. ~840 MB download, ~2-3 min total. Idempotent.
#
# Usage:
#   ./scripts/install-swift.sh
#   export PATH="$HOME/.swift/usr/bin:$PATH"
#   (cd PlusPlusKit && swift test) && (cd PlusPlusCLI && swift test)
set -euo pipefail

VERSION="${SWIFT_VERSION:-6.1}"
DEST="${SWIFT_INSTALL_DIR:-$HOME/.swift}"

if command -v swift >/dev/null 2>&1; then
  echo "swift already on PATH: $(swift --version 2>/dev/null | head -1)"
  exit 0
fi
if [ -x "$DEST/usr/bin/swift" ]; then
  echo "already installed: $("$DEST/usr/bin/swift" --version 2>/dev/null | head -1)"
  echo "add to PATH: export PATH=\"$DEST/usr/bin:\$PATH\""
  exit 0
fi

. /etc/os-release   # provides VERSION_ID, e.g. 24.04
TARBALL="swift-${VERSION}-RELEASE-ubuntu${VERSION_ID}.tar.gz"
URL="https://download.swift.org/swift-${VERSION}-release/ubuntu${VERSION_ID//./}/swift-${VERSION}-RELEASE/${TARBALL}"

# The session proxy MITMs TLS; trust its CA bundle when present.
CURL_ARGS=(-fSL --retry 3)
[ -f /root/.ccr/ca-bundle.crt ] && CURL_ARGS+=(--cacert /root/.ccr/ca-bundle.crt)

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "downloading $URL"
curl "${CURL_ARGS[@]}" -o "$TMP/swift.tar.gz" "$URL"

mkdir -p "$DEST"
tar xzf "$TMP/swift.tar.gz" -C "$DEST" --strip-components=1
echo "installed: $("$DEST/usr/bin/swift" --version | head -1)"
echo "add to PATH: export PATH=\"$DEST/usr/bin:\$PATH\""
