#include "island_window.h"

#include <dwmapi.h>

#include <cmath>
#include <optional>

#include "flutter/generated_plugin_registrant.h"

#pragma comment(lib, "dwmapi.lib")

namespace {

constexpr wchar_t kClassName[] = L"QINGYA_ISLAND_WINDOW";

UINT GetDpiForWindowSafe(HWND hwnd) {
  HMODULE user32 = LoadLibraryW(L"user32.dll");
  if (!user32) return 96;
  using GetDpiForWindowFn = UINT(WINAPI*)(HWND);
  auto fn = reinterpret_cast<GetDpiForWindowFn>(
      GetProcAddress(user32, "GetDpiForWindow"));
  UINT dpi = 96;
  if (fn && hwnd) {
    dpi = fn(hwnd);
  }
  FreeLibrary(user32);
  return dpi == 0 ? 96 : dpi;
}

int Scale(int value, UINT dpi) {
  return static_cast<int>(std::lround(value * dpi / 96.0));
}

}  // namespace

IslandWindow& IslandWindow::Instance() {
  static IslandWindow instance;
  return instance;
}

IslandWindow::~IslandWindow() { Destroy(); }

void IslandWindow::BindMainEngine(flutter::FlutterEngine* main_engine) {
  main_engine_ = main_engine;
  if (!main_engine_) return;

  main_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          main_engine_->messenger(), "qingya/island_host",
          &flutter::StandardMethodCodec::GetInstance());

  main_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto& method = call.method_name();
        if (method == "ensure") {
          result->Success(EnsureCreated());
          return;
        }
        if (method == "show") {
          if (EnsureCreated()) {
            Show();
            result->Success(true);
          } else {
            result->Error("create_failed", "Island window create failed");
          }
          return;
        }
        if (method == "hide") {
          Hide();
          result->Success(true);
          return;
        }
        if (method == "sync") {
          if (const auto* json = std::get_if<std::string>(call.arguments())) {
            PushState(*json);
            result->Success(true);
          } else {
            result->Error("bad_args", "sync expects String json");
          }
          return;
        }
        result->NotImplemented();
      });
}

bool IslandWindow::EnsureCreated() {
  if (hwnd_ && controller_) return true;
  if (!CreateNativeWindow()) return false;
  if (!CreateFlutterView()) {
    Destroy();
    return false;
  }
  if (!last_state_json_.empty()) {
    PushState(last_state_json_);
  }
  return true;
}

bool IslandWindow::CreateNativeWindow() {
  if (hwnd_) return true;

  HINSTANCE instance = GetModuleHandle(nullptr);
  WNDCLASSW wc{};
  wc.lpfnWndProc = IslandWindow::WndProc;
  wc.hInstance = instance;
  wc.lpszClassName = kClassName;
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  wc.hbrBackground = static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
  RegisterClassW(&wc);

  // 先用主屏估算位置；DPI 在创建后校正。
  int screen_w = GetSystemMetrics(SM_CXSCREEN);
  int width = Scale(kWidthDip, 96);
  int height = Scale(kHeightDip, 96);
  int x = (screen_w - width) / 2;
  int y = 0;

  hwnd_ = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED | WS_EX_NOACTIVATE,
      kClassName, L"Qingya Island", WS_POPUP, x, y, width, height, nullptr,
      nullptr, instance, this);

  if (!hwnd_) return false;

  ApplyLayeredStyles();
  PositionTopCenter(kWidthDip, kHeightDip);
  // 默认隐藏，等 Dart sync/show
  ShowWindow(hwnd_, SW_HIDE);
  return true;
}

void IslandWindow::ApplyLayeredStyles() {
  if (!hwnd_) return;
  // 整体不透明 alpha=255；由 Flutter 画透明像素 + DWM 扩展实现“无矩形感”。
  SetLayeredWindowAttributes(hwnd_, 0, 255, LWA_ALPHA);
  MARGINS margins = {-1};
  DwmExtendFrameIntoClientArea(hwnd_, &margins);
  BOOL value = TRUE;
  DwmSetWindowAttribute(hwnd_, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, &value,
                        sizeof(value));
}

void IslandWindow::PositionTopCenter(int width_dip, int height_dip) {
  if (!hwnd_) return;
  UINT dpi = GetDpiForWindowSafe(hwnd_);
  int width = Scale(width_dip, dpi);
  int height = Scale(height_dip, dpi);

  HMONITOR monitor = MonitorFromWindow(hwnd_, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO mi{};
  mi.cbSize = sizeof(mi);
  GetMonitorInfo(monitor, &mi);
  int work_w = mi.rcWork.right - mi.rcWork.left;
  int x = mi.rcWork.left + (work_w - width) / 2;
  int y = mi.rcWork.top;  // 吸顶

  SetWindowPos(hwnd_, HWND_TOPMOST, x, y, width, height,
               SWP_NOACTIVATE | SWP_SHOWWINDOW * (visible_ ? 1 : 0));
  if (!visible_) {
    ShowWindow(hwnd_, SW_HIDE);
  }
}

bool IslandWindow::CreateFlutterView() {
  if (controller_) return true;
  if (!hwnd_) return false;

  RECT rect{};
  GetClientRect(hwnd_, &rect);
  int width = rect.right - rect.left;
  int height = rect.bottom - rect.top;
  if (width <= 0) width = Scale(kWidthDip, GetDpiForWindowSafe(hwnd_));
  if (height <= 0) height = Scale(kHeightDip, GetDpiForWindowSafe(hwnd_));

  flutter::DartProject project(L"data");
  project.set_dart_entrypoint("islandMain");

  controller_ = std::make_unique<flutter::FlutterViewController>(
      width, height, project);
  if (!controller_->engine() || !controller_->view()) {
    controller_.reset();
    return false;
  }

  // 岛引擎尽量也注册插件，保证 MethodChannel / 字体等可用。
  RegisterPlugins(controller_->engine());

  HWND view = controller_->view()->GetNativeWindow();
  SetParent(view, hwnd_);
  MoveWindow(view, 0, 0, width, height, TRUE);
  ShowWindow(view, SW_SHOW);

  view_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          controller_->engine()->messenger(), "qingya/island_view",
          &flutter::StandardMethodCodec::GetInstance());

  view_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto& method = call.method_name();
        if (method == "open_session" || method == "show_main" ||
            method == "announcement_done") {
          ForwardToMain(method, call.arguments());
          result->Success();
          return;
        }
        result->NotImplemented();
      });

  controller_->ForceRedraw();
  return true;
}

void IslandWindow::ForwardToMain(const std::string& method,
                                 const flutter::EncodableValue* args) {
  if (!main_channel_) return;
  if (args) {
    main_channel_->InvokeMethod(
        method, std::make_unique<flutter::EncodableValue>(*args));
  } else {
    main_channel_->InvokeMethod(method, nullptr);
  }
}

void IslandWindow::Show() {
  if (!EnsureCreated()) return;
  visible_ = true;
  PositionTopCenter(kWidthDip, kHeightDip);
  ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
  SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

void IslandWindow::Hide() {
  visible_ = false;
  if (hwnd_) {
    ShowWindow(hwnd_, SW_HIDE);
  }
}

void IslandWindow::PushState(const std::string& json) {
  last_state_json_ = json;
  if (!EnsureCreated()) return;
  if (view_channel_) {
    view_channel_->InvokeMethod(
        "sync", std::make_unique<flutter::EncodableValue>(json));
  }
  // 有状态且启用时由 Dart 侧再决定 show；这里若已 visible 保持置顶
  if (visible_) {
    SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  }
}

void IslandWindow::Destroy() {
  view_channel_.reset();
  controller_.reset();
  if (hwnd_) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
  visible_ = false;
}

LRESULT CALLBACK IslandWindow::WndProc(HWND hwnd, UINT msg, WPARAM wparam,
                                       LPARAM lparam) {
  if (msg == WM_NCCREATE) {
    auto* cs = reinterpret_cast<CREATESTRUCTW*>(lparam);
    auto* self = static_cast<IslandWindow*>(cs->lpCreateParams);
    SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    return DefWindowProc(hwnd, msg, wparam, lparam);
  }
  auto* self =
      reinterpret_cast<IslandWindow*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
  if (self) {
    return self->HandleMessage(hwnd, msg, wparam, lparam);
  }
  return DefWindowProc(hwnd, msg, wparam, lparam);
}

LRESULT IslandWindow::HandleMessage(HWND hwnd, UINT msg, WPARAM wparam,
                                    LPARAM lparam) {
  if (controller_) {
    std::optional<LRESULT> result =
        controller_->HandleTopLevelWindowProc(hwnd, msg, wparam, lparam);
    if (result) {
      return *result;
    }
  }

  switch (msg) {
    case WM_SIZE: {
      if (controller_ && controller_->view()) {
        RECT rect{};
        GetClientRect(hwnd, &rect);
        MoveWindow(controller_->view()->GetNativeWindow(), 0, 0,
                   rect.right - rect.left, rect.bottom - rect.top, TRUE);
      }
      return 0;
    }
    case WM_DPICHANGED: {
      PositionTopCenter(kWidthDip, kHeightDip);
      return 0;
    }
    case WM_NCHITTEST:
      // 整窗可点（岛内容自己处理）；不拖动标题栏。
      return HTCLIENT;
    case WM_DESTROY:
      // 不退出进程
      hwnd_ = nullptr;
      return 0;
    default:
      break;
  }
  return DefWindowProc(hwnd, msg, wparam, lparam);
}
