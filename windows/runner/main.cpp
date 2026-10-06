#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr const wchar_t kSingleInstanceMutexName[] =
    L"Local\\AdventurersGuildFlutterClient";
constexpr const wchar_t kWindowClassName[] =
    L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr const wchar_t kWindowTitle[] =
    L"\u5192\u9669\u8005\u516c\u4f1a";

HWND FindExistingInstanceWindow() {
  // Current builds use the Flutter runner class and a stable title. Keeping
  // the title fallback also catches an already-running older build that did
  // not yet participate in the mutex protocol.
  HWND existing = ::FindWindowW(kWindowClassName, kWindowTitle);
  if (existing != nullptr) {
    return existing;
  }
  return ::FindWindowW(nullptr, kWindowTitle);
}

bool RestoreExistingInstance() {
  // The first process can still be between mutex creation and window creation,
  // so briefly retry instead of launching a second Flutter engine.
  for (int attempt = 0; attempt < 40; ++attempt) {
    HWND existing = FindExistingInstanceWindow();
    if (existing != nullptr) {
      if (::IsIconic(existing)) {
        ::ShowWindow(existing, SW_RESTORE);
      } else {
        ::ShowWindow(existing, SW_SHOW);
      }
      ::BringWindowToTop(existing);
      ::SetForegroundWindow(existing);
      return true;
    }
    ::Sleep(50);
  }
  return false;
}

HANDLE CreateSingleInstanceMutex(DWORD* error) {
  SECURITY_DESCRIPTOR descriptor{};
  SECURITY_ATTRIBUTES attributes{};
  SECURITY_ATTRIBUTES* security = nullptr;

  // A process started by the installer, a desktop shortcut, or another shell
  // can run at a different integrity level. Give the per-session mutex a null
  // DACL so all processes in the user's session can open the same object.
  if (::InitializeSecurityDescriptor(
          &descriptor, SECURITY_DESCRIPTOR_REVISION) != FALSE &&
      ::SetSecurityDescriptorDacl(
          &descriptor, TRUE, nullptr, FALSE) != FALSE) {
    attributes.nLength = sizeof(attributes);
    attributes.lpSecurityDescriptor = &descriptor;
    attributes.bInheritHandle = FALSE;
    security = &attributes;
  }

  ::SetLastError(ERROR_SUCCESS);
  HANDLE handle =
      ::CreateMutexW(security, TRUE, kSingleInstanceMutexName);
  *error = ::GetLastError();
  return handle;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // First catch a legacy/already-visible instance before relying on the named
  // mutex. This makes upgrading from builds that allowed multiple instances
  // self-healing as soon as the next process is launched.
  if (FindExistingInstanceWindow() != nullptr) {
    RestoreExistingInstance();
    return EXIT_SUCCESS;
  }

  DWORD mutex_error = ERROR_SUCCESS;
  HANDLE single_instance_mutex = CreateSingleInstanceMutex(&mutex_error);
  if ((single_instance_mutex != nullptr &&
       mutex_error == ERROR_ALREADY_EXISTS) ||
      (single_instance_mutex == nullptr &&
       mutex_error == ERROR_ACCESS_DENIED)) {
    RestoreExistingInstance();
    if (single_instance_mutex != nullptr) {
      ::CloseHandle(single_instance_mutex);
    }
    return EXIT_SUCCESS;
  }

  // If Windows failed to create the mutex for an unexpected reason, do one
  // more window-level guard instead of silently allowing another instance.
  if (single_instance_mutex == nullptr) {
    if (RestoreExistingInstance()) {
      return EXIT_SUCCESS;
    }
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(kWindowTitle, origin, size)) {
    if (single_instance_mutex != nullptr) {
      ::ReleaseMutex(single_instance_mutex);
      ::CloseHandle(single_instance_mutex);
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (single_instance_mutex != nullptr) {
    ::ReleaseMutex(single_instance_mutex);
    ::CloseHandle(single_instance_mutex);
  }
  return EXIT_SUCCESS;
}
