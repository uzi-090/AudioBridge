#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root/ios"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is required. Install it with: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate --spec project.yml

derived_data="$project_root/artifacts/ios-device"
xcodebuild \
  -project AudioBridgeReceiver.xcodeproj \
  -scheme AudioBridgeReceiver \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

app_path="$derived_data/Build/Products/Release-iphoneos/AudioBridge.app"
package_dir="$project_root/artifacts/ios-package"
mkdir -p "$package_dir/Payload"
ditto "$app_path" "$package_dir/Payload/AudioBridge.app"
(
  cd "$package_dir"
  zip -qry "$project_root/artifacts/AudioBridge-unsigned.ipa" Payload
)

echo "Unsigned IPA: $project_root/artifacts/AudioBridge-unsigned.ipa"
