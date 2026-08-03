#!/bin/bash
# Build macOS agent แบบเซ็นจริง (Apple Development, team PACZDCF6UF)
#
# ทำไมไม่ใช้ flutter build ตรงๆ: flutter build macos เซ็น ad-hoc เสมอ (ไม่ apply
# DEVELOPMENT_TEAM จาก pbxproj) → ทุก rebuild cdhash เปลี่ยน → macOS ถือเป็นแอปใหม่ →
# Screen Recording permission (ScreenCaptureKit/flutter_webrtc) หลุด ต้อง grant+restart
# ทุกรอบ. xcodebuild ตรงพร้อม override จะเซ็นด้วย identity จริง → ลายเซ็นคงที่ข้าม build
# → grant ครั้งเดียวติดถาวร.
#
# ห้ามใช้ `codesign --force --deep` re-sign มือ — ทำ Flutter framework พัง (เคยพังจริง)
set -e
cd "$(dirname "$0")"

echo "==> flutter build macos --debug (สร้าง ephemeral/plugin files)"
flutter build macos --debug

echo "==> xcodebuild re-build พร้อม signing จริง"
cd macos
xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Debug build \
  DEVELOPMENT_TEAM=PACZDCF6UF CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
  -allowProvisioningUpdates -quiet
cd ..

APP=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 5 -iname "myarap.app" -path "*Runner-*" -path "*Debug*" 2>/dev/null | head -1)
echo "==> signature:"
codesign -dv "$APP" 2>&1 | grep -iE "TeamIdentifier|Signature=|Authority=Apple Dev" || true
echo "==> done: $APP"
echo "    เปิดด้วย: open '$APP'"
echo "    (signed จริง — Screen Recording grant ครั้งเดียวติดถาวรข้าม build)"
