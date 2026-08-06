#include "remote_banner.h"

#include <windows.h>
#include <windowsx.h>  // GET_X_LPARAM / GET_Y_LPARAM

#include <cstdio>      // swprintf_s
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

// กรอบปุ่ม "หยุด" — ใช้ทั้งตอนวาดและตอน hit-test ต้องเป็นค่าเดียวกันเสมอ
constexpr int kBtnX = 378, kBtnY = 6, kBtnW = 80, kBtnH = 28;

struct State {
  std::vector<HWND> windows;
  std::wstring viewer;
  bool controlling = false;
  // เวลาเริ่ม session — 0 = ไม่มี session อยู่
  ULONGLONG started_at = 0;
  ULONGLONG esc_down_since = 0;
  std::function<void()> on_stop;
  bool stopping = false;
};

State& S() {
  static State s;
  return s;
}

COLORREF AccentFrom(bool controlling) {
  // แดง = ถูกควบคุม · ฟ้าเขียว = ถูกดู (ชุดสีเดียวกับ macOS และ mockup)
  return controlling ? RGB(0xb3, 0x21, 0x3f) : RGB(0x1b, 0x8f, 0xa3);
}
COLORREF AccentTo(bool controlling) {
  return controlling ? RGB(0xd1, 0x3a, 0x5c) : RGB(0x3f, 0xb6, 0xc9);
}

void FireStop() {
  auto& s = S();
  if (s.stopping) return;  // กันยิงซ้ำตอนปิดหลายหน้าต่างพร้อมกัน
  s.stopping = true;
  auto cb = s.on_stop;
  if (cb) cb();
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
      const int x = GET_X_LPARAM(lp);
      const int y = GET_Y_LPARAM(lp);
      if (x >= kBtnX && x <= kBtnX + kBtnW && y >= kBtnY &&
          y <= kBtnY + kBtnH) {
        FireStop();
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
      // ⚠️ GetAsyncKeyState แยกไม่ออกว่า Esc มาจากเจ้าของเครื่องหรือจาก SendInput
      // ของฝั่งที่ควบคุมอยู่ (ต่างจาก macOS ที่ประทับลายเซ็นลง CGEvent แล้วกรองได้)
      // ผลที่แย่ที่สุดคือ "หยุดการควบคุม" ซึ่งเป็นฝั่งปลอดภัย จึงยอมรับไว้ก่อน
      if (s.controlling) {
        const bool down = (GetAsyncKeyState(VK_ESCAPE) & 0x8000) != 0;
        if (down) {
          if (s.esc_down_since == 0) {
            s.esc_down_since = GetTickCount64();
          } else if (GetTickCount64() - s.esc_down_since >= kEscHoldMs) {
            s.esc_down_since = 0;
            FireStop();
          }
        } else {
          s.esc_down_since = 0;
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

void Show(const std::wstring& viewer, bool controlling) {
  auto& s = S();
  const bool had_session = s.started_at != 0;
  DestroyAll();
  EnsureClass();
  s.viewer = viewer;
  s.controlling = controlling;
  s.esc_down_since = 0;
  if (!had_session) s.started_at = GetTickCount64();
  EnumDisplayMonitors(nullptr, nullptr, AddBannerForMonitor, 0);
}

void Hide() {
  DestroyAll();
  S().started_at = 0;
}

void SetOnStop(std::function<void()> callback) {
  S().on_stop = std::move(callback);
}

}  // namespace remote_banner
