#!/usr/bin/env bash
#
# Ship the current working tree to TestFlight, end to end:
#   bump build number -> regenerate project -> test -> archive -> upload
#   -> wait for processing -> attach to the beta group.
#
# Usage: scripts/testflight-release.sh [--skip-tests]
#
# Requires scripts/asc-config.sh (see the .template alongside it).

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$PWD"

CONFIG="$REPO_ROOT/scripts/asc-config.sh"
[[ -f "$CONFIG" ]] || {
  echo "Missing $CONFIG — copy asc-config.sh.template and fill it in." >&2
  exit 1
}
# shellcheck disable=SC1090
source "$CONFIG"

SKIP_TESTS=0
[[ "${1:-}" == "--skip-tests" ]] && SKIP_TESTS=1

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
INFO_PLIST="$REPO_ROOT/Lightstack/Info.plist"
ARCHIVE="/tmp/Lightstack.xcarchive"
SIM='platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'

AUTH=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$ASC_KEY_PATH"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
)

step() { printf '\n==> %s\n' "$1"; }

# --- 1. Bump the build number -------------------------------------------------
# CFBundleVersion is authoritative: GENERATE_INFOPLIST_FILE is NO, so the literal
# in Info.plist wins over CURRENT_PROJECT_VERSION. Keep both in step anyway.
CURRENT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")
NEXT=$((CURRENT + 1))
step "Bumping build $CURRENT -> $NEXT"
# Patch the XML in place rather than using `PlistBuddy -c Set`, which rewrites
# the whole file: it reorders keys alphabetically and silently drops comments.
python3 - "$INFO_PLIST" "$NEXT" <<'PY'
import re, sys

path, version = sys.argv[1], sys.argv[2]
with open(path) as f:
    text = f.read()
patched, count = re.subn(
    r"(<key>CFBundleVersion</key>\s*<string>)[^<]*(</string>)",
    rf"\g<1>{version}\g<2>",
    text,
    count=1,
)
if count != 1:
    sys.exit("Could not find CFBundleVersion in " + path)
with open(path, "w") as f:
    f.write(patched)
PY
/usr/bin/sed -i '' "s/CURRENT_PROJECT_VERSION: .*/CURRENT_PROJECT_VERSION: $NEXT/" "$REPO_ROOT/project.yml"

step "Regenerating Xcode project"
xcodegen generate >/dev/null

# --- 2. Test ------------------------------------------------------------------
if [[ $SKIP_TESTS -eq 0 ]]; then
  step "Running tests"
  set -o pipefail
  xcodebuild test -project Lightstack.xcodeproj -scheme Lightstack \
    -destination "$SIM" 2>&1 | grep -E "Executed .* tests|error:" | tail -5
fi

# --- 3. Archive ---------------------------------------------------------------
step "Archiving"
rm -rf "$ARCHIVE"
xcodebuild archive -project Lightstack.xcodeproj -scheme Lightstack \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  "${AUTH[@]}" -quiet

# --- 4. Export + upload -------------------------------------------------------
# CODE_SIGN_IDENTITY stays unset and signingStyle automatic: the archive is
# development-signed and gets re-signed for distribution here.
EXPORT_OPTS=$(mktemp -t ExportOptions).plist
cat >"$EXPORT_OPTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>upload</string>
    <key>teamID</key><string>$ASC_TEAM_ID</string>
    <key>uploadSymbols</key><true/>
    <key>manageAppVersionAndBuildNumber</key><true/>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST

step "Exporting and uploading to App Store Connect"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT_OPTS" "${AUTH[@]}" 2>&1 | tail -5

# --- 5. Wait for processing ---------------------------------------------------
PY="$REPO_ROOT/scripts/.venv/bin/python"
if [[ ! -x "$PY" ]]; then
  step "Creating Python venv for the App Store Connect API"
  python3 -m venv "$REPO_ROOT/scripts/.venv"
  "$REPO_ROOT/scripts/.venv/bin/pip" install -q pyjwt cryptography certifi
fi

step "Waiting for build $NEXT to finish processing"
BUILD_ID=""
for _ in $(seq 1 40); do
  BUILD_ID=$("$PY" "$REPO_ROOT/scripts/asc_api.py" \
    "/v1/builds?filter%5Bapp%5D=$ASC_APP_ID&limit=10&sort=-uploadedDate" \
    | "$PY" -c "
import json,sys
want='$NEXT'
for b in json.load(sys.stdin)['data']:
    if b['attributes']['version']==want and b['attributes']['processingState']=='VALID':
        print(b['id']); break
")
  [[ -n "$BUILD_ID" ]] && break
  echo "  still processing..."
  sleep 45
done

[[ -n "$BUILD_ID" ]] || { echo "Build $NEXT did not become VALID in time." >&2; exit 1; }
echo "  build $NEXT is VALID ($BUILD_ID)"

# --- 6. Attach to the beta group ---------------------------------------------
if [[ -n "${ASC_BETA_GROUP_ID:-}" ]]; then
  step "Adding build $NEXT to the TestFlight group"
  "$PY" "$REPO_ROOT/scripts/asc_api.py" \
    "/v1/betaGroups/$ASC_BETA_GROUP_ID/relationships/builds" POST \
    "{\"data\":[{\"type\":\"builds\",\"id\":\"$BUILD_ID\"}]}" >/dev/null
fi

step "Build $NEXT is live on TestFlight."
echo "Remember to commit the build bump:"
echo "  git add Lightstack/Info.plist project.yml Lightstack.xcodeproj/project.pbxproj"
echo "  git commit -m 'build: bump to build $NEXT for TestFlight'"
