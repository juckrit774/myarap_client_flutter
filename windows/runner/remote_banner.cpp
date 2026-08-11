#include "remote_banner.h"

#include <windows.h>
#include <windowsx.h>  // GET_X_LPARAM / GET_Y_LPARAM

#include <atomic>
#include <cstdio>      // swprintf_s
#include <future>
#include <thread>
#include <vector>

namespace remote_banner {

namespace {

constexpr wchar_t kClassName[] = L"MYARAP_REMOTE_BANNER";
constexpr int kWidth = 470;
constexpr int kHeight = 40;
constexpr int kRadius = 9;
constexpr UINT_PTR kTimerId = 1;
constexpr int kTickMs = 250;
// Esc ค้างครบเท่านี้ = หยุดทันที (ทางออกฉุกเฉินตอนเมาส์อยู่ในมือคนอื่น)
constexpr int kEscHoldMs = 2000;
// ลายเซ็นใน dwExtraInfo ของ event ที่ agent ยิงเอง — ต้องตรงกับ `kMyarapInjectedTag`
// ใน lib/core/services/remote_input_windows.dart
constexpr LPARAM kMyarapInjectedTag = 0x4D594152;

// กรอบปุ่ม "หยุด" — ใช้ทั้งตอนวาดและตอน hit-test ต้องเป็นค่าเดียวกันเสมอ
constexpr int kBtnX = 378, kBtnY = 6, kBtnW = 80, kBtnH = 28;

struct State {
  std::vector<HWND> windows;
  std::wstring viewer;
  bool controlling = false;
  // เวลาเริ่ม session — 0 = ไม่มี session อยู่
  ULONGLONG started_at = 0;
  ULONGLONG esc_down_since = 0;
  std::function<void(const char*)> on_stop;
  bool stopping = false;

};

// ── low-level hooks: ตัวเดียวที่แยก "คนหน้าเครื่อง" ออกจาก "ฝั่งที่ควบคุมอยู่" ได้จริง ──
//
// 🔴 ปุ่ม "หยุด" และ Esc ค้าง เป็นทางออกของ**คนหน้าเครื่อง** ฝั่งที่ควบคุมอยู่ต้องกดไม่ได้
// ของเดิมกันไว้คนละแบบและรั่วทั้งคู่:
//   · ปุ่ม → `GetMessageExtraInfo()` คืนค่าของ **ข้อความล่าสุดที่ดึงจากคิว** ถ้า WndProc
//     ถูกเรียกโดยไม่ผ่านคิว ค่าจะเป็นของข้อความอื่น (มักเป็น 0) → ด่านผ่านฉลุย
//   · Esc → `GetAsyncKeyState` **ไม่มีข้อมูลที่มา** แยก injected ไม่ได้เลยตั้งแต่ต้น
// LL hook เห็น `LLMHF_INJECTED`/`LLKHF_INJECTED` + `dwExtraInfo` ของทุก event ตรง ๆ
// (เทียบเท่า global monitor + eventSourceUserData ที่ฝั่ง macOS ใช้อยู่)
//
// 🔴🔴 **hook ต้องอยู่บนเธรดของตัวเอง ห้ามอยู่บนเธรดหลัก** — LL hook ทั้งระบบถูกเรียก
// เข้ามาที่เธรดที่ติดตั้งไว้ ทุก event ของทั้งเครื่องต้องรอ callback นี้ตอบก่อนถึงจะถูกส่งต่อ
// เธรดหลักของ Flutter รัน Dart + capture หน้าจอ + encode JPEG ทุก 400ms จึงค้างเกิน
// `LowLevelHooksTimeout` (ปกติ 300ms) ได้ง่ายมาก ผลคือ:
//   · Windows ข้าม hook ของเราไปเงียบ ๆ → ธง injected ไม่ถูกอัปเดต → **ด่านรั่วเหมือนเดิม**
//   · อินพุตของทั้งเครื่องหน่วง/หล่น — **เจอของจริง**: กด ✕ ของหน้าต่าง agent ผ่าน remote
//     แล้วปุ่มขึ้นไฮไลต์แต่หน้าต่างไม่ปิด เพราะคลิกถูกหน่วงจนแอปไม่นับเป็นคลิก
// เธรดแยกไม่มีอะไรมาบล็อก callback จึงตอบทันทีเสมอ
std::thread g_hook_thread;
DWORD g_hook_tid = 0;
std::atomic<bool> g_hooks_ready{false};
// ปุ่มซ้ายที่ปล่อยล่าสุด "ถูกยิงเข้ามา" หรือไม่ — WM_LBUTTONUP อ่านค่านี้แทน GetMessageExtraInfo
std::atomic<bool> g_last_lbup_injected{false};
// เวลาที่ Esc (ของจริง ไม่ใช่ที่ถูกยิงเข้ามา) เริ่มถูกกดค้าง — 0 = ไม่ได้กดอยู่
std::atomic<ULONGLONG> g_esc_down_since{0};

State& S() {
  static State s;
  return s;
}

// ⚠️ callback สองตัวนี้รันบน **เธรด hook** ไม่ใช่เธรดหลัก — แตะได้เฉพาะตัวแปร atomic
// และต้องคืนค่าให้เร็วที่สุด (ทุก event ของทั้งเครื่องรออยู่)
LRESULT CALLBACK LlMouseProc(int code, WPARAM wp, LPARAM lp) {
  if (code == HC_ACTION && wp == WM_LBUTTONUP) {
    const auto* ms = reinterpret_cast<const MSLLHOOKSTRUCT*>(lp);
    g_last_lbup_injected.store(
        (ms->flags & LLMHF_INJECTED) != 0 ||
        ms->dwExtraInfo == static_cast<ULONG_PTR>(kMyarapInjectedTag));
  }
  return CallNextHookEx(nullptr, code, wp, lp);
}

LRESULT CALLBACK LlKeyProc(int code, WPARAM wp, LPARAM lp) {
  if (code == HC_ACTION) {
    const auto* ks = reinterpret_cast<const KBDLLHOOKSTRUCT*>(lp);
    if (ks->vkCode == VK_ESCAPE) {
      // ⚠️ กรอง **injected ทุกชนิด** ไม่ใช่เฉพาะลายเซ็นของเรา — ทางออกฉุกเฉินนี้มีไว้ให้
      // "คนที่นั่งอยู่หน้าเครื่อง" เท่านั้น อะไรที่ถูกยิงเข้ามาไม่นับทั้งหมด
      // แลกกับ: on-screen keyboard / โปรแกรมช่วยเหลือที่ยิง Esc จะใช้ทางนี้ไม่ได้
      // (ยังกดปุ่ม "หยุด" บนแถบได้ตามปกติ จึงไม่ได้ทำให้ไม่มีทางออก)
      const bool injected =
          (ks->flags & LLKHF_INJECTED) != 0 ||
          ks->dwExtraInfo == static_cast<ULONG_PTR>(kMyarapInjectedTag);
      if (!injected) {
        if (wp == WM_KEYDOWN || wp == WM_SYSKEYDOWN) {
          ULONGLONG expected = 0;
          g_esc_down_since.compare_exchange_strong(expected, GetTickCount64());
        } else if (wp == WM_KEYUP || wp == WM_SYSKEYUP) {
          g_esc_down_since.store(0);
        }
      }
    }
  }
  return CallNextHookEx(nullptr, code, wp, lp);
}

// เธรดของ hook: ติดตั้ง → ปั๊ม message ของตัวเอง → ถอดตอนได้ WM_QUIT
// ต้องมี message loop เป็นของตัวเอง ไม่งั้น LL hook ไม่ถูกเรียกเลย
void HookThreadMain(std::promise<bool> ready) {
  g_hook_tid = GetCurrentThreadId();
  HINSTANCE mod = GetModuleHandle(nullptr);
  HHOOK mh = SetWindowsHookExW(WH_MOUSE_LL, LlMouseProc, mod, 0);
  HHOOK kh = SetWindowsHookExW(WH_KEYBOARD_LL, LlKeyProc, mod, 0);
  const bool ok = mh != nullptr && kh != nullptr;
  g_hooks_ready.store(ok);
  ready.set_value(ok);

  MSG msg;
  while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
    // ไม่ต้อง dispatch อะไร — เธรดนี้มีไว้ให้ hook ถูกเรียกอย่างเดียว
  }

  if (mh) UnhookWindowsHookEx(mh);
  if (kh) UnhookWindowsHookEx(kh);
  g_hooks_ready.store(false);
  g_hook_tid = 0;
}

void InstallHooks() {
  if (g_hook_thread.joinable()) return;  // ติดตั้งไว้แล้ว (Show() ถูกเรียกซ้ำได้)
  g_last_lbup_injected.store(false);
  g_esc_down_since.store(0);
  std::promise<bool> pr;
  auto fut = pr.get_future();
  g_hook_thread = std::thread(HookThreadMain, std::move(pr));
  // รอให้ติดตั้งเสร็จก่อนคืน — ไม่งั้นคลิกแรก ๆ จะยังไม่มีตัวกัน
  fut.wait_for(std::chrono::milliseconds(1000));
}

void RemoveHooks() {
  if (!g_hook_thread.joinable()) return;
  if (g_hook_tid) PostThreadMessageW(g_hook_tid, WM_QUIT, 0, 0);
  g_hook_thread.join();
  g_last_lbup_injected.store(false);
  g_esc_down_since.store(0);
}

COLORREF AccentFrom(bool controlling) {
  // แดง = ถูกควบคุม · ฟ้าเขียว = ถูกดู (ชุดสีเดียวกับ macOS และ mockup)
  return controlling ? RGB(0xb3, 0x21, 0x3f) : RGB(0x1b, 0x8f, 0xa3);
}
COLORREF AccentTo(bool controlling) {
  return controlling ? RGB(0xd1, 0x3a, 0x5c) : RGB(0x3f, 0xb6, 0xc9);
}

void FireStop(const char* reason) {
  auto& s = S();
  if (s.stopping) return;  // กันยิงซ้ำตอนปิดหลายหน้าต่างพร้อมกัน
  s.stopping = true;
  auto cb = s.on_stop;
  if (cb) cb(reason);
  s.stopping = false;
}

// ไล่สีแนวนอนแบบเขียนเอง — GdiGradientFill ต้องลิงก์ msimg32 เพิ่ม
// ในขณะที่แถบกว้างแค่ 470px การวาดทีละคอลัมน์ถูกกว่าการเพิ่ม dependency
void FillGradient(HDC dc, const RECT& rc, COLORREF a, COLORREF b) {
  const int w = rc.right - rc.left;
  if (w <= 0) return;
  for (int x = 0; x < w; ++x) {
    const double t = static_cast<double>(x) / w;
    const COLORREF c = RGB(
        static_cast<int>(GetRValue(a) + (GetRValue(b) - GetRValue(a)) * t),
        static_cast<int>(GetGValue(a) + (GetGValue(b) - GetGValue(a)) * t),
        static_cast<int>(GetBValue(a) + (GetBValue(b) - GetBValue(a)) * t));
    RECT col{rc.left + x, rc.top, rc.left + x + 1, rc.bottom};
    HBRUSH br = CreateSolidBrush(c);
    FillRect(dc, &col, br);
    DeleteObject(br);
  }
}

HFONT MakeFont(int height, int weight, const wchar_t* face) {
  return CreateFontW(height, 0, 0, 0, weight, FALSE, FALSE, FALSE,
                     DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                     CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, face);
}

void PaintBanner(HWND hwnd) {
  auto& s = S();
  PAINTSTRUCT ps;
  HDC dc = BeginPaint(hwnd, &ps);

  RECT rc;
  GetClientRect(hwnd, &rc);
  FillGradient(dc, rc, AccentFrom(s.controlling), AccentTo(s.controlling));

  SetBkMode(dc, TRANSPARENT);
  SetTextColor(dc, RGB(255, 255, 255));

  // จุดขาว + วงแหวนจาง — ไม่มี alpha ใน GDI ธรรมดา จึงผสมสีวงแหวนเองกับพื้นตรงนั้น
  // (28% ขาวบนสีพื้นซ้ายสุด ซึ่งเป็นตำแหน่งที่จุดอยู่พอดี)
  const COLORREF base = AccentFrom(s.controlling);
  const COLORREF halo = RGB(GetRValue(base) + (255 - GetRValue(base)) * 28 / 100,
                            GetGValue(base) + (255 - GetGValue(base)) * 28 / 100,
                            GetBValue(base) + (255 - GetBValue(base)) * 28 / 100);
  HBRUSH halo_br = CreateSolidBrush(halo);
  HBRUSH white_br = CreateSolidBrush(RGB(255, 255, 255));
  HPEN null_pen = static_cast<HPEN>(GetStockObject(NULL_PEN));
  HPEN old_pen = static_cast<HPEN>(SelectObject(dc, null_pen));
  HBRUSH old_br = static_cast<HBRUSH>(SelectObject(dc, halo_br));
  Ellipse(dc, 12, 13, 27, 28);
  SelectObject(dc, white_br);
  Ellipse(dc, 15, 16, 24, 25);
  SelectObject(dc, old_br);
  SelectObject(dc, old_pen);
  DeleteObject(halo_br);
  DeleteObject(white_br);

  // ชื่อคนดูหนา ส่วนคำอธิบายน้ำหนักปกติ — ให้สายตาจับ "ใคร" ได้ก่อน "กำลังทำอะไร"
  HFONT bold = MakeFont(-15, FW_BOLD, L"Segoe UI");
  HFONT regular = MakeFont(-15, FW_NORMAL, L"Segoe UI");
  HFONT mono = MakeFont(-12, FW_NORMAL, L"Consolas");

  HFONT old_font = static_cast<HFONT>(SelectObject(dc, bold));
  SIZE name_sz{};
  GetTextExtentPoint32W(dc, s.viewer.c_str(),
                        static_cast<int>(s.viewer.size()), &name_sz);
  const int text_y = (kHeight - name_sz.cy) / 2;
  TextOutW(dc, 30, text_y, s.viewer.c_str(), static_cast<int>(s.viewer.size()));

  const std::wstring tail = s.controlling
                                ? L" กำลังควบคุมเมาส์และคีย์บอร์ดของเครื่องนี้"
                                : L" กำลังดูหน้าจอของคุณ";
  SelectObject(dc, regular);
  TextOutW(dc, 30 + name_sz.cx, text_y, tail.c_str(),
           static_cast<int>(tail.size()));

  // เวลาที่ถูกดูมาแล้ว ชิดขวาก่อนถึงปุ่ม
  const ULONGLONG ms =
      s.started_at ? (GetTickCount64() - s.started_at) : 0;
  const int total_s = static_cast<int>(ms / 1000);
  wchar_t clock[16];
  swprintf_s(clock, L"%02d:%02d", total_s / 60, total_s % 60);
  SelectObject(dc, mono);
  RECT clock_rc{296, 0, 366, kHeight};
  DrawTextW(dc, clock, -1, &clock_rc,
            DT_RIGHT | DT_SINGLELINE | DT_VCENTER);

  // ปุ่มขาวตัวอักษรสีเดียวกับแถบ — ปุ่มสีจางจมหายไปกับพื้นไล่สี ทั้งที่เป็นสิ่งเดียว
  // ในแถบนี้ที่ผู้ใช้ต้องกดติดตั้งแต่ครั้งแรก
  HBRUSH btn_br = CreateSolidBrush(RGB(255, 255, 255));
  RECT btn{kBtnX, kBtnY, kBtnX + kBtnW, kBtnY + kBtnH};
  HRGN btn_rgn = CreateRoundRectRgn(btn.left, btn.top, btn.right + 1,
                                    btn.bottom + 1, 12, 12);
  FillRgn(dc, btn_rgn, btn_br);
  DeleteObject(btn_rgn);
  DeleteObject(btn_br);

  HFONT btn_font = MakeFont(-13, FW_SEMIBOLD, L"Segoe UI");
  SelectObject(dc, btn_font);
  SetTextColor(dc, AccentFrom(s.controlling));
  DrawTextW(dc, L"หยุด", -1, &btn, DT_CENTER | DT_SINGLELINE | DT_VCENTER);

  SelectObject(dc, old_font);
  DeleteObject(bold);
  DeleteObject(regular);
  DeleteObject(mono);
  DeleteObject(btn_font);

  EndPaint(hwnd, &ps);
}

LRESULT CALLBACK BannerProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  switch (msg) {
    case WM_PAINT:
      PaintBanner(hwnd);
      return 0;

    case WM_ERASEBKGND:
      return 1;  // วาดพื้นเองใน WM_PAINT — ไม่งั้นกะพริบทุกวินาทีตอนอัปเดตเวลา

    case WM_LBUTTONUP: {
      // 🔴 ปุ่ม "หยุด" เป็นของ**คนหน้าเครื่อง** — คลิกที่ถูกยิงเข้ามาต้องไม่นับ
      // ไม่งั้นฝั่งที่ควบคุมอยู่กดจบ session ของเจ้าของเครื่องได้
      //
      // เชื่อ LL hook ก่อนเสมอ (เห็น LLMHF_INJECTED ตรง ๆ) · ถ้าติดตั้ง hook ไม่สำเร็จ
      // ค่อยถอยไปใช้ `GetMessageExtraInfo()` ตัวเดิม — รั่วได้แต่ดีกว่าไม่กันเลย
      if (g_hooks_ready.load() ? g_last_lbup_injected.load()
                               : (GetMessageExtraInfo() == kMyarapInjectedTag)) {
        return 0;
      }
      const int x = GET_X_LPARAM(lp);
      const int y = GET_Y_LPARAM(lp);
      if (x >= kBtnX && x <= kBtnX + kBtnW && y >= kBtnY &&
          y <= kBtnY + kBtnH) {
        FireStop(g_hooks_ready.load() ? "btn" : "btn-nohook");
      }
      return 0;
    }

    case WM_SETCURSOR:
      SetCursor(LoadCursor(nullptr, IDC_ARROW));
      return TRUE;

    case WM_TIMER: {
      if (wp != kTimerId) break;
      auto& s = S();
      // วาดใหม่เฉพาะกรอบตัวเลขเวลา ไม่ใช่ทั้งแถบ — ทั้งแถบทุก 250ms จะเห็นกะพริบ
      // (WM_PAINT clip ตามกรอบนี้ ส่วนพื้นไล่สีจึงถูกวาดทับเฉพาะที่จำเป็น)
      RECT clock_rc{296, 0, 366, kHeight};
      InvalidateRect(hwnd, &clock_rc, FALSE);

      // Esc ค้าง — เฉพาะตอนถูกควบคุม เพราะปุ่มหยุดต้องใช้เมาส์ซึ่งอยู่ในมือคนอื่น
      //
      // เมื่อมี kbd hook: `esc_down_since` ถูกตั้ง/ล้างจาก hook ซึ่งนับเฉพาะ Esc ที่
      // **ไม่ได้ถูกยิงเข้ามา** · ตรงนี้เหลือหน้าที่แค่จับเวลาว่าค้างครบหรือยัง
      //
      // ⚠️ ทางถอย (hook ติดตั้งไม่สำเร็จ) ยังใช้ GetAsyncKeyState ซึ่ง **แยกที่มาไม่ได้**
      // จึงแยกชื่อเหตุเป็น `esc-nohook` ไว้ใน log — เห็นค่านี้เมื่อไรแปลว่ากลับไปใช้ทางที่รั่ว
      if (s.controlling) {
        if (g_hooks_ready.load()) {
          const ULONGLONG since = g_esc_down_since.load();
          if (since != 0 && GetTickCount64() - since >= kEscHoldMs) {
            g_esc_down_since.store(0);
            FireStop("esc");
          }
        } else {
          const bool down = (GetAsyncKeyState(VK_ESCAPE) & 0x8000) != 0;
          if (down) {
            if (s.esc_down_since == 0) {
              s.esc_down_since = GetTickCount64();
            } else if (GetTickCount64() - s.esc_down_since >= kEscHoldMs) {
              s.esc_down_since = 0;
              FireStop("esc-nohook");
            }
          } else {
            s.esc_down_since = 0;
          }
        }
      }
      return 0;
    }
  }
  return DefWindowProc(hwnd, msg, wp, lp);
}

void EnsureClass() {
  static bool registered = false;
  if (registered) return;
  WNDCLASSW wc{};
  wc.lpfnWndProc = BannerProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = kClassName;
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  RegisterClassW(&wc);
  registered = true;
}

BOOL CALLBACK AddBannerForMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM) {
  MONITORINFO mi{};
  mi.cbSize = sizeof(mi);
  if (!GetMonitorInfo(monitor, &mi)) return TRUE;

  const int x =
      mi.rcMonitor.left + (mi.rcMonitor.right - mi.rcMonitor.left) / 2 -
      kWidth / 2;
  const int y = mi.rcMonitor.top + 6;

  HWND hwnd = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, kClassName, L"",
      WS_POPUP, x, y, kWidth, kHeight, nullptr, nullptr,
      GetModuleHandle(nullptr), nullptr);
  if (!hwnd) return TRUE;

  HRGN rgn = CreateRoundRectRgn(0, 0, kWidth + 1, kHeight + 1, kRadius * 2,
                                kRadius * 2);
  SetWindowRgn(hwnd, rgn, TRUE);  // ระบบเป็นเจ้าของ rgn หลังจากนี้ ห้าม DeleteObject

  // NOACTIVATE + SW_SHOWNOACTIVATE — แถบต้องไม่แย่ง focus จากสิ่งที่ผู้ใช้ทำอยู่
  ShowWindow(hwnd, SW_SHOWNOACTIVATE);
  UpdateWindow(hwnd);
  SetTimer(hwnd, kTimerId, kTickMs, nullptr);
  S().windows.push_back(hwnd);
  return TRUE;
}

void DestroyAll() {
  auto& s = S();
  for (HWND h : s.windows) {
    KillTimer(h, kTimerId);
    DestroyWindow(h);
  }
  s.windows.clear();
}

}  // namespace

int Show(const std::wstring& viewer, bool controlling) {
  auto& s = S();
  const bool had_session = s.started_at != 0;
  DestroyAll();
  EnsureClass();
  // ติดตั้ง hook ตอนแถบขึ้น (= มี session อยู่) เท่านั้น — ไม่ดักอินพุตทั้งเครื่องทิ้งไว้ตลอดเวลา
  // `Show()` ถูกเรียกซ้ำได้ตอนสลับ ดู↔ควบคุม จึงต้อง idempotent (InstallHooks เช็คให้แล้ว)
  InstallHooks();
  s.viewer = viewer;
  s.controlling = controlling;
  s.esc_down_since = 0;   // ทางถอย (ไม่มี hook)
  g_esc_down_since.store(0);
  if (!had_session) s.started_at = GetTickCount64();
  EnumDisplayMonitors(nullptr, nullptr, AddBannerForMonitor, 0);
  return static_cast<int>(s.windows.size());
}

void Hide() {
  DestroyAll();
  RemoveHooks();  // จบ session แล้วต้องเลิกดักอินพุตทั้งเครื่องทันที
  S().started_at = 0;
}

void SetOnStop(std::function<void(const char*)> callback) {
  S().on_stop = std::move(callback);
}

}  // namespace remote_banner
