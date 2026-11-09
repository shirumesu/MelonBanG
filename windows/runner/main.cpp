#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Brings back the copy already running for this user, such as one waiting
// in the tray when the shortcut is opened again, so that two processes
// never share the database and the downloads. Returns whether one runs.
// A separate MELONBANG_DATA_DIR keeps its own data, and may run beside it.
bool ActivateRunningCopy() {
  if (::GetEnvironmentVariableW(L"MELONBANG_DATA_DIR", nullptr, 0) > 0) {
    return false;
  }
  // Held until this process exits; the system releases it even on a crash.
  HANDLE mutex =
      ::CreateMutexW(nullptr, TRUE, L"Local\\org.melonbang.melonbang");
  if (::GetLastError() != ERROR_ALREADY_EXISTS) return false;
  if (HWND window =
          ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"MelonBanG")) {
    ::ShowWindow(window, ::IsIconic(window) ? SW_RESTORE : SW_SHOW);
    ::SetForegroundWindow(window);
    return true;
  }
  // No window means the other copy is past closing it and still shutting its
  // services down; start once it has gone rather than doing nothing.
  const DWORD waited = ::WaitForSingleObject(mutex, 30000);
  return waited != WAIT_OBJECT_0 && waited != WAIT_ABANDONED;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  if (ActivateRunningCopy()) {
    return EXIT_SUCCESS;
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
  if (!window.Create(L"MelonBanG", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
