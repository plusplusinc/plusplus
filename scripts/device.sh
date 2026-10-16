#!/bin/bash
# Builds the app for a physical iPhone, installs it, and launches it; with no iPhone in reach,
# makes an install link instead.
#
#   scripts/device.sh                                  # the one available iPhone, else a link
#   PLUSPLUS_DEVICE="<name or UDID>" scripts/device.sh
#   scripts/device.sh --link                           # a link, even with an iPhone in reach
#
# The phone is looked up each time, never stored, since the repo is public. It must be paired
# with this Mac and reachable: devicectl marks it unavailable when it is away or off the Mac's
# Wi-Fi, and then the script makes a link. A locked phone that is reachable takes the install
# but not the launch, and the script says to open the app there. The build is incremental in the
# worktree's .build/device, apart from the simulator's derived data so both can build at once.
#
# The link is a development-signed .ipa, an install manifest, and a one-button page, deployed
# under a fresh random path as static assets of a Cloudflare Worker on workers.dev. Opened in
# Safari on a phone in the team's provisioning profile, Install installs the build. Every
# worktree stages its builds in the main checkout's .build/phone-link/site, and a deploy serves
# only the latest two there, so older links stop working. The Worker's name and host come from
# the environment or Config/Local.xcconfig (this worktree's, else the main checkout's), never
# from the repo:
#
#   PLUSPLUS_BUILDS_WORKER = <worker name>
#   PLUSPLUS_BUILDS_HOST = <worker name>.<account subdomain>.workers.dev
#
# A host, not a URL, because xcconfig reads // as the start of a comment. Deploying needs
# wrangler, logged in to the account.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DERIVED_DATA="$ROOT/.build/device"
# The archive and export are this worktree's; the site deployed from is shared by all of them.
MAIN=$(dirname "$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)")
STAGING="$ROOT/.build/phone-link"
SITE="$MAIN/.build/phone-link"
mkdir -p "$STAGING"

# One line per available iPhone, UDID then name, tab-separated, narrowed to PLUSPLUS_DEVICE
# when it is set. devicectl also lists simulators, watches, and devices it cannot reach. Names
# are compared with typographic apostrophes and spaces made plain, so a typed name matches.
available_iphones() {
    xcrun devicectl list devices --quiet --json-output - | python3 -c '
import json, sys

def plain(text):
    return text.replace("\u2019", "\x27").replace("\u00a0", " ").casefold()

wanted = plain(sys.argv[1])
for device in json.load(sys.stdin)["result"]["devices"]:
    properties = device.get("properties", {})
    hardware = properties.get("hardware", {})
    connection = properties.get("connection", {})
    name = properties.get("state", {}).get("name", "")
    if (
        hardware.get("reality") == "physical"
        and hardware.get("deviceType") == "iPhone"
        and connection.get("pairingState") == "paired"
        and connection.get("state", "unavailable") != "unavailable"
        and wanted in ("", plain(hardware.get("udid", "")), plain(name))
    ):
        print(hardware["udid"], name, sep="\t")
' "${PLUSPLUS_DEVICE:-}"
}

# Prints a link setting from the environment, else from the last line setting it in a
# Config/Local.xcconfig, or fails naming what to set.
link_setting() {
    if [ -n "${!1:-}" ]; then
        echo "${!1}"
        return
    fi
    local file value
    for file in "$ROOT/Config/Local.xcconfig" "$MAIN/Config/Local.xcconfig"; do
        value=$(sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\([^[:space:]]*\).*/\1/p" \
            "$file" 2> /dev/null | tail -n 1)
        if [ -n "$value" ]; then
            echo "$value"
            return
        fi
    done
    echo "no $1 for the install link: set it in the environment or Config/Local.xcconfig," \
        "as the top of scripts/device.sh says" >&2
    return 78
}

# Archives and exports a development-signed .ipa, stages it with its manifest and page under a
# fresh random path, deploys the latest two staged builds, and prints the page's URL once the
# manifest is served.
install_link() {
    local worker host
    worker=$(link_setting PLUSPLUS_BUILDS_WORKER)
    host=$(link_setting PLUSPLUS_BUILDS_HOST)
    if ! command -v wrangler > /dev/null; then
        echo "wrangler is not installed; the install link deploys with it" >&2
        return 69
    fi

    local archive="$STAGING/$SCHEME.xcarchive" exported="$STAGING/export"
    DESTINATION="generic/platform=iOS"
    run_xcodebuild device-archive archive -configuration Debug -archivePath "$archive" \
        -allowProvisioningUpdates

    cat > "$STAGING/ExportOptions.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>method</key><string>debugging</string></dict></plist>
PLIST
    rm -rf "$exported"
    xcodebuild -exportArchive -archivePath "$archive" -exportPath "$exported" \
        -exportOptionsPlist "$STAGING/ExportOptions.plist" -allowProvisioningUpdates 2>&1 |
        beautify

    local token build note=""
    token=$(openssl rand -hex 16)
    build="$SITE/site/$token"
    mkdir -p "$build"
    # A build that never deploys is removed on exit, so it can't take one of the two places.
    UNDEPLOYED="$build"
    trap '[ -z "${UNDEPLOYED:-}" ] || rm -rf "$UNDEPLOYED"' EXIT
    mv "$exported/$SCHEME.ipa" "$build/"
    if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
        note="Includes uncommitted changes."
    fi
    python3 - "$archive/Products/Applications/$SCHEME.app/Info.plist" "https://$host/$token" \
        "$build" "$SCHEME.ipa" "$(git -C "$ROOT" log -1 --format=%s)" \
        "$(date '+%a %b %-d, %-I:%M %p')" "$note" << 'PYTHON'
import html, plistlib, sys

info_path, base, build, ipa, subject, built, note = sys.argv[1:]
with open(info_path, "rb") as file:
    info = plistlib.load(file)
name = info.get("CFBundleDisplayName") or info["CFBundleName"]

with open(f"{build}/manifest.plist", "wb") as file:
    plistlib.dump({"items": [{
        "assets": [{"kind": "software-package", "url": f"{base}/{ipa}"}],
        "metadata": {
            "bundle-identifier": info["CFBundleIdentifier"],
            "bundle-version": info["CFBundleShortVersionString"],
            "kind": "software",
            "title": name,
        },
    }]}, file)

lines = [subject, f"Built {built}"] + ([note] if note else [])
paragraphs = "\n".join(f"<p>{html.escape(line)}</p>" for line in lines)
install = html.escape(f"itms-services://?action=download-manifest&url={base}/manifest.plist")
with open(f"{build}/index.html", "w") as file:
    file.write(f"""<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex">
<title>{html.escape(name)}</title>
<style>
body {{ font: 17px -apple-system, system-ui; background: #1f1e1c; color: #f0ede6;
  margin: 0; padding: 48px 24px; }}
p {{ color: #9b978e; }}
a {{ display: block; margin-top: 32px; padding: 16px; border-radius: 11px; background: #f0ede6;
  color: #161616; font-weight: 600; text-align: center; text-decoration: none; }}
</style>
<h1>{html.escape(name)}</h1>
{paragraphs}
<a href="{install}">Install</a>
""")
PYTHON

    # Keep the newest two builds; the deploy replaces every asset, so the rest stop being served.
    local old
    ls -dt "$SITE"/site/*/ | tail -n +3 | while IFS= read -r old; do rm -rf "$old"; done

    # Static assets get no content type for extensions the Worker doesn't know; these are the
    # ones Apple's over-the-air install expects.
    cat > "$SITE/site/_headers" << 'HEADERS'
/:build/manifest.plist
  Content-Type: text/xml
/:build/*.ipa
  Content-Type: application/octet-stream
HEADERS

    # Assets only: no script, no root page, a 404 for any path that isn't a file, and no
    # per-version preview URLs that would keep serving old builds.
    cat > "$SITE/wrangler.jsonc" << JSON
{
  "name": "$worker",
  "compatibility_date": "2026-10-01",
  "assets": { "directory": "./site", "not_found_handling": "none" },
  "workers_dev": true,
  "preview_urls": false
}
JSON
    if ! (cd "$SITE" && wrangler deploy > "$SITE/deploy.log" 2>&1); then
        cat "$SITE/deploy.log" >&2
        echo "wrangler deploy failed" >&2
        return 1
    fi
    UNDEPLOYED=""

    # New assets can take about a minute to reach every edge.
    local manifest="https://$host/$token/manifest.plist" deadline=$((SECONDS + 120))
    until curl --silent --fail --output /dev/null "$manifest"; do
        if [ "$SECONDS" -ge "$deadline" ]; then
            echo "deployed, but not yet served after two minutes; it may still come up at" \
                "https://$host/$token/" >&2
            return 1
        fi
        sleep 5
    done
    echo "install link: https://$host/$token/"
}

case "${1:-}" in
    "") ;;
    --link)
        install_link
        exit
        ;;
    *)
        echo "usage: scripts/device.sh [--link]" >&2
        exit 64
        ;;
esac

IPHONES=$(available_iphones)
COUNT=$(grep -c . <<< "$IPHONES" || true)

if [ "$COUNT" -eq 0 ]; then
    echo "no iPhone available${PLUSPLUS_DEVICE:+ matching PLUSPLUS_DEVICE=$PLUSPLUS_DEVICE}," \
        "so making an install link; xcrun devicectl list devices shows what it sees"
    install_link
    exit
fi
if [ "$COUNT" -gt 1 ]; then
    echo "more than one iPhone available; choose one with PLUSPLUS_DEVICE=\"<name or UDID>\":" >&2
    cut -f2 <<< "$IPHONES" | sed 's/^/  /' >&2
    exit 64
fi
IFS=$'\t' read -r UDID NAME <<< "$IPHONES"

DESTINATION="id=$UDID"
run_xcodebuild device build -configuration Debug \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration

APP="$DERIVED_DATA/Build/Products/Debug-iphoneos/$SCHEME.app"
BUNDLE_ID=$(app_bundle_id "$APP")
if ! xcrun devicectl device install app --quiet --device "$UDID" "$APP"; then
    echo "built, but could not install on $NAME; if it stays out of reach," \
        "scripts/device.sh --link makes an install link" >&2
    exit 69
fi
# A locked phone takes the install but refuses the launch. The build is on the phone either way.
if ! xcrun devicectl device process launch --quiet --terminate-existing --device "$UDID" \
    "$BUNDLE_ID"; then
    echo "installed on $NAME, but not launched (devicectl says why above; usually it is locked):" \
        "open PlusPlus there"
    exit 0
fi
echo "launched on $NAME"
