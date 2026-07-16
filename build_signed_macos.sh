#!/bin/bash
# Build macOS agent — เซ็นด้วย Apple Development อัตโนมัติ (DEVELOPMENT_TEAM ตั้งใน project.pbxproj)
# จำเป็นสำหรับ ScreenCaptureKit (Remote screen-recording indicator) ที่ต้องการ stable signature
# (ad-hoc "-" ใช้ SCK ไม่ได้). ไม่ใช้ codesign --deep มือ เพราะทำ Flutter framework พัง
set -e
cd "$(dirname "$0")"
echo "==> flutter build macos --debug (automatic signing, team PACZDCF6UF)"
flutter build macos --debug
APP="build/macos/Build/Products/Debug/myarap.app"
echo "==> signature:"
codesign -dv "$APP" 2>&1 | grep -iE "TeamIdentifier|Signature=" || true
echo "==> done: $PWD/$APP"
