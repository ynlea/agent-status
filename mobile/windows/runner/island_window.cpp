#include "island_window.h"

#include <cmath>
#include <optional>

// 注意：岛引擎不 RegisterPlugins，避免托盘/window_manager 双实例冲突。

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
        if (method == "set_size") {
          const auto* map = std::get_if<flutter::EncodableMap>(call.arguments());
          if (!map) {
            result->Error("bad_args", "set_size expects map");
            return;
          }
          int w = width_dip_;
          int h = height_dip_;
          auto itw = map->find(flutter::EncodableValue("width"));
          auto ith = map->find(flutter::EncodableValue("height"));
          if (itw != map->end()) {
            if (const auto* v = std::get_if<int32_t>(&itw->second)) w = *v;
            if (const auto* v = std::get_if<double>(&itw->second))
              w = static_cast<int>(*v);
          }
          if (ith != map->end()) {
            if (const auto* v = std::get_if<int32_t>(&ith->second)) h = *v;
            if (const auto* v = std::get_if<double>(&ith->second))
              h = static_cast<int>(*v);
          }
          SetContentSize(w, h);
          result->Success(true);
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
  // 不用 DWM 全透明扩展，避免“看不见却挡点击”的玻璃空窗。
  wc.hbrBackground = CreateSolidBrush(RGB(28, 24, 22));
  RegisterClassW(&wc);

  int screen_w = GetSystemMetrics(SM_CXSCREEN);
  int width = Scale(width_dip_, 96);
  int height = Scale(height_dip_, 96);
  int x = (screen_w - width) / 2;
  int y = 0;

  hwnd_ = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
      kClassName, L"", WS_POPUP, x, y, width, height, nullptr, nullptr,
      instance, this);

  if (!hwnd_) return false;

  ApplyWindowStyles();
  PositionTopCenter();
  ShowWindow(hwnd_, SW_HIDE);
  return true;
}

void IslandWindow::ApplyWindowStyles() {
  if (!hwnd_) return;
  // 保持置顶工具窗；不做 LWA 全窗透明（Flutter 子 HWND 在 layered 下常整片透明）。
  LONG ex = GetWindowLong(hwnd_, GWL_EXSTYLE);
  ex |= WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE;
  ex &= ~WS_EX_LAYERED;
  SetWindowLong(hwnd_, GWL_EXSTYLE, ex);
}

void IslandWindow::PositionTopCenter() {
  if (!hwnd_) return;
  UINT dpi = GetDpiForWindowSafe(hwnd_);
  int width = Scale(width_dip_, dpi);
  int height = Scale(height_dip_, dpi);

  HMONITOR monitor = MonitorFromWindow(hwnd_, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO mi{};
  mi.cbSize = sizeof(mi);
  GetMonitorInfo(monitor, &mi);
  int work_w = mi.rcWork.right - mi.rcWork.left;
  int x = mi.rcWork.left + (work_w - width) / 2;
  int y = mi.rcWork.top;

  UINT flags = SWP_NOACTIVATE;
  if (visible_) flags |= SWP_SHOWWINDOW;
  SetWindowPos(hwnd_, HWND_TOPMOST, x, y, width, height, flags);
  if (controller_ && controller_->view()) {
    MoveWindow(controller_->view()->GetNativeWindow(), 0, 0, width, height,
               TRUE);
  }
  if (!visible_) {
    ShowWindow(hwnd_, SW_HIDE);
  }
}

void IslandWindow::SetContentSize(int width_dip, int height_dip) {
  if (width_dip < 80) width_dip = 80;
  if (height_dip < 28) height_dip = 28;
  if (width_dip > 480) width_dip = 480;
  if (height_dip > 360) height_dip = 360;
  width_dip_ = width_dip;
  height_dip_ = height_dip;
  if (hwnd_) {
    PositionTopCenter();
  }
}

bool IslandWindow::CreateFlutterView() {
  if (controller_) return true;
  if (!hwnd_) return false;

  RECT rect{};
  GetClientRect(hwnd_, &rect);
  int width = rect.right - rect.left;
  int height = rect.bottom - rect.top;
  if (width <= 0) width = Scale(width_dip_, GetDpiForWindowSafe(hwnd_));
  if (height <= 0) height = Scale(height_dip_, GetDpiForWindowSafe(hwnd_));

  flutter::DartProject project(L"data");
  project.set_dart_entrypoint("islandMain");

  controller_ = std::make_unique<flutter::FlutterViewController>(
      width, height, project);
  if (!controller_->engine() || !controller_->view()) {
    controller_.reset();
    return false;
  }

  // 不注册插件：岛 UI 仅需 MethodChannel + 自绘。
  HWND view = controller_->view()->GetNativeWindow();
  SetParent(view, hwnd_);
  LONG style = GetWindowLong(view, GWL_STYLE);
  style |= WS_CHILD;
  style &= ~WS_POPUP;
  SetWindowLong(view, GWL_STYLE, style);
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
            method == "announcement_done" || method == "set_size") {
          if (method == "set_size") {
            // 岛引擎请求改尺寸：在本窗处理
            const auto* map =
                std::get_if<flutter::EncodableMap>(call.arguments());
            if (map) {
              int w = width_dip_;
              int h = height_dip_;
              auto itw = map->find(flutter::EncodableValue("width"));
              auto ith = map->find(flutter::EncodableValue("height"));
              if (itw != map->end()) {
                if (const auto* v = std::get_if<double>(&itw->second))
                  w = static_cast<int>(*v);
                if (const auto* v = std::get_if<int32_t>(&itw->second)) w = *v;
              }
              if (ith != map->end()) {
                if (const auto* v = std::get_if<double>(&ith->second))
                  h = static_cast<int>(*v);
                if (const auto* v = std::get_if<int32_t>(&ith->second)) h = *v;
              }
              SetContentSize(w, h);
            }
            result->Success();
            return;
          }
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
  PositionTopCenter();
  ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
  SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  if (controller_) {
    controller_->ForceRedraw();
  }
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
  if (visible_) {
    SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    if (controller_) controller_->ForceRedraw();
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
    case WM_ERASEBKGND:
      return 1;
    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC hdc = BeginPaint(hwnd, &ps);
      RECT rc;
      GetClientRect(hwnd, &rc);
      HBRUSH brush = CreateSolidBrush(RGB(28, 24, 22));
      FillRect(hdc, &rc, brush);
      DeleteObject(brush);
      EndPaint(hwnd, &ps);
      return 0;
    }
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
      PositionTopCenter();
      return 0;
    }
    case WM_NCHITTEST:
      return HTCLIENT;
    case WM_DESTROY:
      hwnd_ = nullptr;
      return 0;
    default:
      break;
  }
  return DefWindowProc(hwnd, msg, wparam, lparam);
}
