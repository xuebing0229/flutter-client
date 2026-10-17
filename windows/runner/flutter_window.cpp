#include "flutter_window.h"

#include <shellapi.h>
#include <shobjidl.h>

#include <cwchar>
#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"
#include "utils.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  // Win32Window::Create() calls Destroy() once before creating the HWND.
  // That path reaches OnDestroy() on an already-constructed FlutterWindow, so
  // always begin a real window lifetime in the non-exiting state.
  exiting_ = false;

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

  windows_file_picker_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "app.windows_file_picker",
          &flutter::StandardMethodCodec::GetInstance());
  windows_file_picker_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "pickBackupFile") {
          result->NotImplemented();
          return;
        }

        IFileOpenDialog* dialog = nullptr;
        HRESULT hr = ::CoCreateInstance(
            CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&dialog));
        if (FAILED(hr) || dialog == nullptr) {
          result->Error(
              "WINDOWS_FILE_PICKER_FAILED",
              "Could not create the Windows file picker.",
              flutter::EncodableValue(static_cast<int64_t>(hr)));
          return;
        }

        FILEOPENDIALOGOPTIONS options = 0;
        hr = dialog->GetOptions(&options);
        if (SUCCEEDED(hr)) {
          hr = dialog->SetOptions(
              options | FOS_FORCEFILESYSTEM | FOS_FILEMUSTEXIST |
              FOS_PATHMUSTEXIST);
        }

        const COMDLG_FILTERSPEC filters[] = {
            {L"Adventure Guild backup", L"*.json;*.zip"}};
        if (SUCCEEDED(hr)) {
          hr = dialog->SetFileTypes(1, filters);
        }

        if (SUCCEEDED(hr)) {
          hr = dialog->Show(GetHandle());
        }
        if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
          dialog->Release();
          result->Success();
          return;
        }
        if (FAILED(hr)) {
          dialog->Release();
          result->Error(
              "WINDOWS_FILE_PICKER_FAILED",
              "Windows could not open the selected backup file.",
              flutter::EncodableValue(static_cast<int64_t>(hr)));
          return;
        }

        IShellItem* item = nullptr;
        hr = dialog->GetResult(&item);
        if (FAILED(hr) || item == nullptr) {
          dialog->Release();
          result->Error(
              "WINDOWS_FILE_PICKER_FAILED",
              "Windows did not return the selected backup file.",
              flutter::EncodableValue(static_cast<int64_t>(hr)));
          return;
        }

        wchar_t* wide_path = nullptr;
        hr = item->GetDisplayName(SIGDN_FILESYSPATH, &wide_path);
        item->Release();
        dialog->Release();

        if (FAILED(hr) || wide_path == nullptr) {
          if (wide_path != nullptr) {
            ::CoTaskMemFree(wide_path);
          }
          result->Error(
              "WINDOWS_FILE_PICKER_FAILED",
              "The selected item does not expose a filesystem path.",
              flutter::EncodableValue(static_cast<int64_t>(hr)));
          return;
        }

        const std::string path = Utf8FromUtf16(wide_path);
        ::CoTaskMemFree(wide_path);
        if (path.empty()) {
          result->Error(
              "WINDOWS_FILE_PICKER_FAILED",
              "Windows returned an empty filesystem path.",
              nullptr);
          return;
        }

        result->Success(flutter::EncodableValue(path));
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  taskbar_created_message_ = ::RegisterWindowMessageW(L"TaskbarCreated");
  AddTrayIcon();

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
  RemoveTrayIcon();

  windows_file_picker_channel_.reset();

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::AddTrayIcon() {
  if (tray_icon_added_ || GetHandle() == nullptr) {
    return;
  }

  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = kTrayIconId;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  data.uCallbackMessage = kTrayCallbackMessage;
  data.hIcon = ::LoadIconW(
      ::GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
  ::wcsncpy_s(data.szTip, ARRAYSIZE(data.szTip), L"\u5192\u9669\u8005\u516c\u4f1a",
              _TRUNCATE);

  tray_icon_added_ = ::Shell_NotifyIconW(NIM_ADD, &data) != FALSE;
  if (tray_icon_added_) {
    data.uVersion = NOTIFYICON_VERSION_4;
    ::Shell_NotifyIconW(NIM_SETVERSION, &data);
  }
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_icon_added_ || GetHandle() == nullptr) {
    tray_icon_added_ = false;
    return;
  }

  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = kTrayIconId;
  ::Shell_NotifyIconW(NIM_DELETE, &data);
  tray_icon_added_ = false;
}

void FlutterWindow::RestoreFromTray() {
  HWND window = GetHandle();
  if (window == nullptr) {
    return;
  }

  ::ShowWindow(window, SW_RESTORE);
  ::SetForegroundWindow(window);
  ::BringWindowToTop(window);
}

void FlutterWindow::ShowTrayMenu() {
  HWND window = GetHandle();
  if (window == nullptr) {
    return;
  }

  HMENU menu = ::CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }

  ::AppendMenuW(menu, MF_STRING, kTrayOpenCommand,
                L"\u6253\u5f00\u5192\u9669\u8005\u516c\u4f1a");
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING, kTrayExitCommand,
                L"\u9000\u51fa\u5192\u9669\u8005\u516c\u4f1a");

  POINT cursor{};
  ::GetCursorPos(&cursor);

  // Required by TrackPopupMenu so the menu dismisses normally when clicking
  // elsewhere.
  ::SetForegroundWindow(window);
  const UINT command = ::TrackPopupMenu(
      menu, TPM_RIGHTBUTTON | TPM_RETURNCMD | TPM_NONOTIFY,
      cursor.x, cursor.y, 0, window, nullptr);
  ::PostMessageW(window, WM_NULL, 0, 0);
  ::DestroyMenu(menu);

  if (command == kTrayOpenCommand) {
    RestoreFromTray();
  } else if (command == kTrayExitCommand) {
    exiting_ = true;
    RemoveTrayIcon();
    Destroy();
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (taskbar_created_message_ != 0 &&
      message == taskbar_created_message_) {
    // Explorer recreates the notification area after a shell restart.
    tray_icon_added_ = false;
    AddTrayIcon();
    return 0;
  }

  switch (message) {
    case WM_CLOSE:
      // The title-bar close button and Alt+F4 keep the app alive for sync and
      // local reminders. "Exit" in the tray menu is the explicit quit path.
      if (!exiting_) {
        // Re-add the icon if Explorer restarted or the first registration was
        // delayed. Only fall back to a real close when Windows still refuses
        // to create the tray icon, otherwise the hidden app would be
        // impossible to restore.
        if (!tray_icon_added_) {
          AddTrayIcon();
        }
        if (tray_icon_added_) {
          ::ShowWindow(hwnd, SW_HIDE);
          return 0;
        }
      }
      break;

    case kTrayCallbackMessage: {
      // LOWORD works for both legacy NOTIFYICON callbacks and version 4.
      const UINT event = LOWORD(static_cast<DWORD_PTR>(lparam));
      if (event == WM_LBUTTONDBLCLK) {
        RestoreFromTray();
      } else if (event == WM_RBUTTONUP || event == WM_CONTEXTMENU) {
        ShowTrayMenu();
      }
      return 0;
    }
  }

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
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
