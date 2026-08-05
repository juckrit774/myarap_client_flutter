#!/bin/bash
# สร้าง DMG สำหรับติดตั้ง MyARAP บน macOS (drag-to-Applications)
#
# ใช้ .app ที่ **เซ็นแล้ว** จาก build_signed_macos.sh เท่านั้น — ห้ามใช้ผลของ
# `flutter build macos` ตรง ๆ เพราะเซ็นแบบ ad-hoc → ลายเซ็นเปลี่ยนทุก build →
# ผู้ใช้ต้อง grant Screen Recording / Accessibility ใหม่ทุกครั้งที่อัปเดต
#
# ปลายทาง: อาร์กิวเมนต์ที่ 1 (ไม่ใส่ = โฟลเดอร์ปัจจุบัน)
set -e
cd "$(dirname "$0")"

OUT_DIR="${1:-$PWD}"
VER=$(grep -m1 'MYARAP_DISPLAY_VERSION' macos/Runner/Configs/AppInfo.xcconfig | awk -F'= *' '{print $2}' | tr -d ' ')
DMG="$OUT_DIR/MyARAP-${VER}.dmg"

# หา .app จาก 2 ที่: DerivedData (ผลของ build_signed_macos.sh) แล้ว fallback ไป
# /Applications (ตัวที่ติดตั้งไว้) — DerivedData ถูกล้างได้ทุกครั้งที่ rebuild
APP=""
for c in \
  "$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 5 -iname "MyARAP.app" -path "*Runner-*" -path "*/Build/Products/Debug/*" 2>/dev/null | head -1)" \
  "/Applications/MyARAP.app"
do
  [ -n "$c" ] && [ -d "$c" ] && { APP="$c"; break; }
done
[ -z "$APP" ] && { echo "✗ ไม่พบ MyARAP.app — รัน ./build_signed_macos.sh ก่อน"; exit 1; }

echo "==> ใช้ app: $APP"
echo "    build เมื่อ: $(stat -f '%Sm' "$APP/Contents/MacOS/MyARAP")"
# ต้องเซ็นด้วย identity จริง ไม่ใช่ ad-hoc — ไม่งั้นผู้ใช้ต้อง grant สิทธิ์ใหม่ทุกอัปเดต
codesign -dv "$APP" 2>&1 | grep -E "TeamIdentifier" || { echo "✗ ไม่ได้เซ็น (ad-hoc?)"; exit 1; }
codesign --verify --deep --strict "$APP" || { echo "✗ ลายเซ็นไม่สมบูรณ์"; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # ให้ผู้ใช้ลากไปติดตั้งได้เลย

mkdir -p "$OUT_DIR"
rm -f "$DMG"
echo "==> สร้าง DMG"
hdiutil create -volname "MyARAP $VER" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"

echo "==> เสร็จ: $DMG"
echo "    ขนาด: $(du -h "$DMG" | cut -f1)"
