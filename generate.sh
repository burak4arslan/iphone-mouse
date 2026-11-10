#!/bin/bash
# Generates the Xcode project for the iPhone app. Optional first: cp Config/local.env.example Config/local.env and fill it in.
set -euo pipefail
cd "$(dirname "$0")"
command -v xcodegen >/dev/null || { echo "XcodeGen is required: brew install xcodegen"; exit 1; }
if [ -f Config/local.env ]; then
  # shellcheck disable=SC1091
  source Config/local.env
else
  echo "No Config/local.env: using the default bundle ID (pick your team in Xcode > Signing & Capabilities)"
fi
export IPHONEFARE_TEAM_ID="${IPHONEFARE_TEAM_ID:-}"
export IPHONEFARE_BUNDLE_ID="${IPHONEFARE_BUNDLE_ID:-com.example.iphonefare}"
xcodegen generate
echo "Done: IPhoneFare.xcodeproj (bundle ID $IPHONEFARE_BUNDLE_ID)"
