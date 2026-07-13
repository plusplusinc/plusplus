#!/bin/bash
# Bootstrap the Axiom plugin (Apple-platform skills + agents) for remote / web
# sessions. Axiom is declared in .claude/settings.json (extraKnownMarketplaces
# + enabledPlugins), but that does NOT auto-install it into an ephemeral remote
# container — every fresh cloud session starts without it unless we install it
# here. The post-hook container state is cached, so once this runs the plugin is
# baked in and later sessions start with it already on disk (and loaded).
#
# Idempotent, non-interactive, and offline-safe: a network failure must never
# block session start, so every step degrades to a no-op.
set -uo pipefail

# Local (Mac) sessions manage their own plugins and have the real Xcode tools;
# only bootstrap the remote environment.
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

# Already present (cached container) → fast no-op.
if claude plugin list 2>/dev/null | grep -q "axiom@axiom-marketplace"; then
  exit 0
fi

# Best-effort install. The marketplace name (axiom-marketplace) is resolved
# from the source repo via settings.json; the timeouts + `|| true` guarantee a
# slow or offline network can't wedge the session.
timeout 150 claude plugin marketplace add CharlesWiltgen/Axiom >/dev/null 2>&1 || true
timeout 150 claude plugin install axiom@axiom-marketplace >/dev/null 2>&1 || true

exit 0
