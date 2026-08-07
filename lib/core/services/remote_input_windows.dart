// Remote Control — input injection ฝั่ง Windows ด้วย `SendInput` (user32.dll)
//
// ทำไมใช้ dart:ffi ไม่ใช่ PowerShell:
//   ที่อื่นในแอปนี้ (USB block / consent / indicator / capture) เรียก PowerShell ผ่าน
//   Process.run ได้เพราะยิงนาน ๆ ครั้ง แต่เมาส์เลื่อนยิง ~60 event/วินาที การ spawn
//   process ต่อ event จะหน่วงเป็นวินาทีและกิน CPU จนใช้งานจริงไม่ได้ → ต้องเรียก API ตรง
//
// ทำไมแยกไฟล์ + lazy load:
//   `DynamicLibrary.open('user32.dll')` จะ throw ทันทีบน macOS/Linux ถ้าเรียกตอน import
//   จึงเปิดไลบรารีตอนใช้ครั้งแรกเท่านั้น (`_u32` เป็น late final) และผู้เรียกต้อง guard
//   ด้วย `Platform.isWindows` ก่อนเสมอ
//
// ⚠️ ข้อจำกัดที่แก้ไม่ได้ในระดับ POC:
//   - **คุม UAC prompt / หน้าจอ Ctrl+Alt+Del / หน้า login ไม่ได้** — เป็น secure desktop
//     คนละ session กับที่ agent รันอยู่ · จะทำได้ต้องรัน agent เป็น Windows service
//     ที่ session 0 ซึ่งเปลี่ยนสถาปัตยกรรมทั้งตัว (นอกขอบเขต POC)
//   - ไม่รองรับหลายจอ — ยิงพิกัดเทียบ **จอหลัก** เท่านั้น
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart'; // calloc — dart:ffi ไม่มี allocator ให้ในตัว

// ── ค่าคงที่จาก Windows SDK (winuser.h) ────────────────────────────────────
const int _inputMouse = 0;
const int _inputKeyboard = 1;

const int _mouseMove = 0x0001;
const int _mouseAbsolute = 0x8000;
const int _mouseLeftDown = 0x0002;
const int _mouseLeftUp = 0x0004;
const int _mouseRightDown = 0x0008;
const int _mouseRightUp = 0x0010;
const int _mouseMiddleDown = 0x0020;
const int _mouseMiddleUp = 0x0040;
const int _mouseWheel = 0x0800;
const int _mouseHWheel = 0x1000;

const int _keyKeyUp = 0x0002;
const int _keyScancode = 0x0008;

/// ลายเซ็นที่ประทับลง `dwExtraInfo` ของทุก event ที่ **เรายิงเอง**
///
/// ทำไมต้องมี: แถบเตือน (`remote_banner.cpp`) มีปุ่ม "หยุด" ซึ่งเป็นของ**คนหน้าเครื่อง**
/// ถ้าฝั่งที่ควบคุมอยู่เลื่อนเมาส์ไปคลิกโดน (ตั้งใจหรือไม่ก็ตาม) session จะจบทันที
/// โดยเจ้าของเครื่องไม่ได้สั่ง · Win32 อ่านค่านี้กลับได้ด้วย `GetMessageExtraInfo()`
/// จึงกรองทิ้งได้ตรงจุด — เทียบเท่ากับที่ฝั่ง macOS ทำผ่าน
/// `CGEvent.setIntegerValueField(.eventSourceUserData)` อยู่แล้ว
///
/// ค่า = 'MYAR' ในรูป ASCII (ต้องตรงกับ `kMyarapInjectedTag` ใน remote_banner.cpp)
const int kMyarapInjectedTag = 0x4D594152;

const int _smCxScreen = 0;
const int _smCyScreen = 1;

/// MOUSEINPUT (winuser.h) — ต้องเรียงและ align ให้ตรงกับ C ไม่งั้น SendInput อ่านค่าเพี้ยน
final class _MouseInput extends Struct {
  @Int32()
  external int dx;
  @Int32()
  external int dy;
  @Uint32()
  external int mouseData;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int time;
  @IntPtr()
  external int dwExtraInfo;
}

/// KEYBDINPUT — union กับ MOUSEINPUT ใน INPUT จึงต้องอยู่ใน buffer ก้อนเดียวกัน
final class _KeybdInput extends Struct {
  @Uint16()
  external int wVk;
  @Uint16()
  external int wScan;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int time;
  @IntPtr()
  external int dwExtraInfo;
}

/// INPUT — `type` แล้วตามด้วย union
/// บน x64 มี padding 4 ไบต์หลัง type (union align 8 เพราะมี ULONG_PTR) → ขนาดรวม 40 ไบต์
/// เราจองเป็น buffer ดิบแล้วเขียนทีละ field เอง เพราะ dart:ffi ยังไม่รองรับ union ตรง ๆ
const int _inputSize = 40;
const int _unionOffset = 8; // type(4) + padding(4)

typedef _SendInputNative = Uint32 Function(Uint32, Pointer<Uint8>, Int32);
typedef _SendInputDart = int Function(int, Pointer<Uint8>, int);
typedef _GetSystemMetricsNative = Int32 Function(Int32);
typedef _GetSystemMetricsDart = int Function(int);

class RemoteInputWindows {
  /// ข้อความผิดพลาดล่าสุด — input ถูกออกแบบให้เงียบ (ไม่ล้ม session) แต่ถ้าเงียบทั้งหมด
  /// จะไล่ปัญหาไม่ได้เลย จึงเก็บไว้ให้ดึงไปแสดง/ส่ง log ได้
  static String? _lastError;
  static String? get lastError => _lastError;

  static DynamicLibrary? _lib;
  static _SendInputDart? _sendInput;
  static _GetSystemMetricsDart? _getMetrics;

  /// เปิด user32.dll ตอนใช้ครั้งแรก — คืน false ถ้าไม่ใช่ Windows หรือโหลดไม่ได้
  static bool _ensure() {
    if (!Platform.isWindows) return false;
    if (_sendInput != null) return true;
    try {
      _lib = DynamicLibrary.open('user32.dll');
      _sendInput = _lib!
          .lookupFunction<_SendInputNative, _SendInputDart>('SendInput');
      _getMetrics = _lib!.lookupFunction<_GetSystemMetricsNative,
          _GetSystemMetricsDart>('GetSystemMetrics');
      _lastError = null;
      return true;
    } catch (e) {
      _lastError = 'โหลด user32.dll ไม่สำเร็จ: $e';
      return false;
    }
  }

  static void _write(Pointer<Uint8> buf, int type,
      {int dx = 0,
      int dy = 0,
      int mouseData = 0,
      int flags = 0,
      int vk = 0,
      int scan = 0}) {
    for (var i = 0; i < _inputSize; i++) {
      buf[i] = 0;
    }
    buf.cast<Uint32>()[0] = type;
    if (type == _inputMouse) {
      final mi = Pointer<_MouseInput>.fromAddress(buf.address + _unionOffset).ref;
      mi.dx = dx;
      mi.dy = dy;
      mi.mouseData = mouseData;
      mi.dwFlags = flags;
      mi.time = 0;
      mi.dwExtraInfo = kMyarapInjectedTag;
    } else {
      final ki = Pointer<_KeybdInput>.fromAddress(buf.address + _unionOffset).ref;
      ki.wVk = vk;
      ki.wScan = scan;
      ki.dwFlags = flags;
      ki.time = 0;
      ki.dwExtraInfo = kMyarapInjectedTag;
    }
  }

  static void _send(
      {required int type,
      int dx = 0,
      int dy = 0,
      int mouseData = 0,
      int flags = 0,
      int vk = 0,
      int scan = 0}) {
    if (!_ensure()) return;
    // ⚠️ ห้ามใช้ `DynamicLibrary.process()` หา malloc/free — **บน Windows โยน
    // UnsupportedError เสมอ** (รองรับเฉพาะ Linux/macOS) เคยใช้แล้วทำให้ input ทุกตัว
    // ถูกทิ้งเงียบ ๆ เพราะ exception ถูก catch ที่ผู้เรียก — ใช้ calloc ของ package:ffi แทน
    final buf = calloc<Uint8>(_inputSize);
    try {
      _write(buf, type,
          dx: dx,
          dy: dy,
          mouseData: mouseData,
          flags: flags,
          vk: vk,
          scan: scan);
      final sent = _sendInput!(1, buf, _inputSize);
      if (sent != 1) _lastError = 'SendInput ส่งได้ $sent จาก 1 event';
    } finally {
      calloc.free(buf);
    }
  }

  /// เลื่อนเมาส์ — nx/ny เป็นสัดส่วน 0..1 ของจอหลัก
  ///
  /// `MOUSEEVENTF_ABSOLUTE` ใช้พิกัดปกติ 0..65535 (ไม่ใช่ pixel) ครอบทั้งจอหลัก
  /// จึงแปลงจากสัดส่วนได้ตรง ๆ โดยไม่ต้องรู้ความละเอียดจริง
  static void mouseMove(double nx, double ny) {
    final x = (nx.clamp(0.0, 1.0) * 65535).round();
    final y = (ny.clamp(0.0, 1.0) * 65535).round();
    _send(type: _inputMouse, dx: x, dy: y, flags: _mouseMove | _mouseAbsolute);
  }

  static void mouseDown(int button) {
    final f = button == 1
        ? _mouseRightDown
        : (button == 2 ? _mouseMiddleDown : _mouseLeftDown);
    _send(type: _inputMouse, flags: f);
  }

  static void mouseUp(int button) {
    final f =
        button == 1 ? _mouseRightUp : (button == 2 ? _mouseMiddleUp : _mouseLeftUp);
    _send(type: _inputMouse, flags: f);
  }

  /// scroll — Windows ใช้ WHEEL_DELTA = 120 ต่อ 1 คลิก และทิศทาง**กลับกับ**เบราว์เซอร์
  /// (deltaY บวก = เลื่อนลง แต่ Windows บวก = เลื่อนขึ้น) จึงต้องกลับเครื่องหมาย
  static void scroll(int dy, int dx) {
    if (dy != 0) {
      _send(
          type: _inputMouse,
          mouseData: -(dy ~/ 100) * 120,
          flags: _mouseWheel);
    }
    if (dx != 0) {
      _send(
          type: _inputMouse, mouseData: (dx ~/ 100) * 120, flags: _mouseHWheel);
    }
  }

  /// กด/ปล่อยปุ่มด้วย **scan code** ไม่ใช่ virtual key
  ///
  /// เหตุผลเดียวกับที่ viewer ส่ง `KeyboardEvent.code` มา: scan code = ตำแหน่งปุ่มจริงบน
  /// คีย์บอร์ด ไม่ขึ้นกับ layout/ภาษาที่เครื่องปลายทางตั้งไว้ — ถ้าใช้ virtual key
  /// เครื่องที่สลับเป็นภาษาไทยจะได้ตัวอักษรผิด
  static void key(int scanCode, {required bool down}) {
    var flags = _keyScancode;
    if (!down) flags |= _keyKeyUp;
    _send(type: _inputKeyboard, vk: 0, scan: scanCode, flags: flags);
  }

  /// KeyboardEvent.code → **scan code (Set 1)** ของ PC keyboard
  /// ค่าตรงกับตำแหน่งปุ่มจริง ไม่ขึ้นกับ layout — เครื่องที่ตั้งเป็นภาษาไทยก็ได้ตัวถูก
  static const Map<String, int> scanMap = {
    'Escape': 0x01, 'Digit1': 0x02, 'Digit2': 0x03, 'Digit3': 0x04, 'Digit4': 0x05,
    'Digit5': 0x06, 'Digit6': 0x07, 'Digit7': 0x08, 'Digit8': 0x09, 'Digit9': 0x0A,
    'Digit0': 0x0B, 'Minus': 0x0C, 'Equal': 0x0D, 'Backspace': 0x0E, 'Tab': 0x0F,
    'KeyQ': 0x10, 'KeyW': 0x11, 'KeyE': 0x12, 'KeyR': 0x13, 'KeyT': 0x14, 'KeyY': 0x15,
    'KeyU': 0x16, 'KeyI': 0x17, 'KeyO': 0x18, 'KeyP': 0x19, 'BracketLeft': 0x1A,
    'BracketRight': 0x1B, 'Enter': 0x1C, 'ControlLeft': 0x1D, 'KeyA': 0x1E, 'KeyS': 0x1F,
    'KeyD': 0x20, 'KeyF': 0x21, 'KeyG': 0x22, 'KeyH': 0x23, 'KeyJ': 0x24, 'KeyK': 0x25,
    'KeyL': 0x26, 'Semicolon': 0x27, 'Quote': 0x28, 'Backquote': 0x29, 'ShiftLeft': 0x2A,
    'Backslash': 0x2B, 'KeyZ': 0x2C, 'KeyX': 0x2D, 'KeyC': 0x2E, 'KeyV': 0x2F,
    'KeyB': 0x30, 'KeyN': 0x31, 'KeyM': 0x32, 'Comma': 0x33, 'Period': 0x34,
    'Slash': 0x35, 'ShiftRight': 0x36, 'AltLeft': 0x38, 'Space': 0x39,
    'F1': 0x3B, 'F2': 0x3C, 'F3': 0x3D, 'F4': 0x3E, 'F5': 0x3F, 'F6': 0x40,
    'F7': 0x41, 'F8': 0x42, 'F9': 0x43, 'F10': 0x44, 'F11': 0x57, 'F12': 0x58,
    // ปุ่มขยาย (extended) — ต้องมี flag 0xE0 นำหน้า ดู keyByCode()
    'Home': 0x47, 'ArrowUp': 0x48, 'PageUp': 0x49, 'ArrowLeft': 0x4B,
    'ArrowRight': 0x4D, 'End': 0x4F, 'ArrowDown': 0x50, 'PageDown': 0x51,
    'Delete': 0x53, 'ControlRight': 0x1D, 'AltRight': 0x38,
  };

  /// ปุ่มที่ต้องส่ง KEYEVENTF_EXTENDEDKEY — ถ้าไม่ใส่ ลูกศร/Delete จะกลายเป็นปุ่ม numpad
  static const Set<String> _extended = {
    'Home', 'ArrowUp', 'PageUp', 'ArrowLeft', 'ArrowRight', 'End', 'ArrowDown',
    'PageDown', 'Delete', 'ControlRight', 'AltRight',
  };
  static const int _keyExtended = 0x0001;

  static void keyByCode(String code, {required bool down}) {
    final sc = scanMap[code];
    if (sc == null) return; // ปุ่มที่ไม่รู้จัก = ทิ้ง ไม่เดา
    var flags = _keyScancode;
    if (_extended.contains(code)) flags |= _keyExtended;
    if (!down) flags |= _keyKeyUp;
    _send(type: _inputKeyboard, vk: 0, scan: sc, flags: flags);
  }

  /// modifier ต้องกดค้างเองก่อน/ปล่อยหลังปุ่มหลัก — SendInput ไม่มี flag รวมแบบ macOS
  static void modifiers({bool shift = false, bool ctrl = false, bool alt = false, required bool down}) {
    if (ctrl) keyByCode('ControlLeft', down: down);
    if (alt) keyByCode('AltLeft', down: down);
    if (shift) keyByCode('ShiftLeft', down: down);
  }

  static ({int w, int h})? screenSize() {
    if (!_ensure()) return null;
    return (w: _getMetrics!(_smCxScreen), h: _getMetrics!(_smCyScreen));
  }
}
