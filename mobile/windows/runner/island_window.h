#ifndef RUNNER_ISLAND_WINDOW_H_
#define RUNNER_ISLAND_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>

#include <memory>
#include <string>

#include <windows.h>

// 原生置顶分层岛窗：独立 Flutter 引擎（islandMain），不进任务栏、不抢焦点。
class IslandWindow {
 public:
  static IslandWindow& Instance();

  // 绑定主引擎，注册 qingya/island_host 通道。
  void BindMainEngine(flutter::FlutterEngine* main_engine);

  bool EnsureCreated();
  void Show();
  void Hide();
  void PushState(const std::string& json);
  void Destroy();

  bool is_created() const { return hwnd_ != nullptr; }

 private:
  IslandWindow() = default;
  ~IslandWindow();

  IslandWindow(const IslandWindow&) = delete;
  IslandWindow& operator=(const IslandWindow&) = delete;

  bool CreateNativeWindow();
  bool CreateFlutterView();
  void PositionTopCenter(int width_dip, int height_dip);
  void ApplyLayeredStyles();
  void ForwardToMain(const std::string& method, const flutter::EncodableValue* args);

  static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wparam,
                                  LPARAM lparam);
  LRESULT HandleMessage(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam);

  HWND hwnd_ = nullptr;
  std::unique_ptr<flutter::FlutterViewController> controller_;
  flutter::FlutterEngine* main_engine_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> main_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> view_channel_;
  std::string last_state_json_;
  bool visible_ = false;

  static constexpr int kWidthDip = 380;
  static constexpr int kHeightDip = 310;
};

#endif  // RUNNER_ISLAND_WINDOW_H_
