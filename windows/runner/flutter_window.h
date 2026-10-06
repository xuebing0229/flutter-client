#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"

// A window that hosts the Flutter view and owns the Windows notification-area
// icon. Closing the window hides it to the tray; the tray menu provides the
// explicit application exit path.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  static constexpr UINT kTrayCallbackMessage = WM_APP + 1;
  static constexpr UINT kTrayIconId = 1;
  static constexpr UINT kTrayOpenCommand = 1001;
  static constexpr UINT kTrayExitCommand = 1002;

  void AddTrayIcon();
  void RemoveTrayIcon();
  void RestoreFromTray();
  void ShowTrayMenu();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  UINT taskbar_created_message_ = 0;
  bool tray_icon_added_ = false;
  bool exiting_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
