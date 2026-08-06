#include "flutter_window.h"

#include <windows.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "remote_banner.h"

namespace {

// Dart ส่งสตริงมาเป็น UTF-8 แต่ Win32 วาดข้อความด้วย UTF-16 — ชื่อผู้ดูแลระบบ
// เป็นภาษาไทยได้ ถ้าแปลงผิดจะกลายเป็นสี่เหลี่ยมบนแถบ
std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return std::wstring();
  const int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(),
                                    static_cast<int>(s.size()), nullptr, 0);
  std::wstring out(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()),
                      out.data(), n);
  return out;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // แถบเตือน remote — ชื่อ channel/method ตรงกับที่ฝั่ง macOS ใช้อยู่แล้ว
  // (`com.myarap/remote` · showIndicator/hideIndicator) เพื่อให้ Dart เรียกทางเดียวกัน
  remote_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "com.myarap/remote",
          &flutter::StandardMethodCodec::GetInstance());

  remote_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "showIndicator") {
          std::string viewer;
          bool controlling = false;
          if (const auto* args =
                  std::get_if<flutter::EncodableMap>(call.arguments())) {
            auto it = args->find(flutter::EncodableValue("viewer"));
            if (it != args->end()) {
              if (const auto* v = std::get_if<std::string>(&it->second)) {
                viewer = *v;
              }
            }
            it = args->find(flutter::EncodableValue("controlling"));
            if (it != args->end()) {
              if (const auto* b = std::get_if<bool>(&it->second)) {
                controlling = *b;
              }
            }
          }
          const int shown = remote_banner::Show(Utf8ToWide(viewer), controlling);
          // คืนจำนวนหน้าต่างให้ Dart บันทึกไว้ — 0 = เรียกถึงแล้วแต่สร้างไม่ได้
          result->Success(flutter::EncodableValue(shown));
        } else if (call.method_name() == "hideIndicator") {
          remote_banner::Hide();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  // ผู้ใช้กด "หยุด" บนแถบ (หรือกด Esc ค้าง) → บอก Dart ให้ตัด session
  // ใช้ InvokeMethod สวนกลับ เพราะฝั่ง Windows ไม่มี EventChannel เหมือน macOS
  remote_banner::SetOnStop([this]() {
    if (remote_channel_) {
      remote_channel_->InvokeMethod("remoteStopByUser", nullptr);
    }
  });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // ปลด callback ก่อนทิ้ง channel — ไม่งั้นแถบที่ยังลอยอยู่ตอนปิดแอปอาจยิง
  // InvokeMethod เข้าที่ channel ที่ถูกทำลายไปแล้ว
  remote_banner::SetOnStop(nullptr);
  remote_banner::Hide();
  remote_channel_ = nullptr;

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
