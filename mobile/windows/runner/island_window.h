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

// 原生置顶岛窗：独立 Flutter 引擎 islandMain；固定小尺寸，内容自绘动画。
class IslandWindow {
 public:
  static IslandWindow& Instance();

  void BindMainEngine(flutter::FlutterEngine* main_engine);

  bool EnsureCreated();
  void Show();
  void Hide();
  void PushState(const std::string& json);
  // 逻辑像素；按内容收紧命中区，避免大块透明挡点击。
  void SetContentSize(int width_dip, int height_dip);
  void Destroy();

  bool is_created() const { return hwnd_ != nullptr; }

 private:
  IslandWindow() = default;
  ~IslandWindow();

  IslandWindow(const IslandWindow&) = delete;
  IslandWindow& operator=(const IslandWindow&) = delete;

  bool CreateNativeWindow();
  bool CreateFlutterView();
  void PositionTopCenter();
  void ApplyWindowStyles();
  void ForwardToMain(const std::string& method,
                     const flutter::EncodableValue* args);

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
  int width_dip_ = 140;
  int height_dip_ = 40;
};

#endif  // RUNNER_ISLAND_WINDOW_H_
