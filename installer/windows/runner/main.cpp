#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shellapi.h>

#include <algorithm>
#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kUninstallKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\MelonBanG";

std::wstring ModuleDirectory() {
  wchar_t path[MAX_PATH];
  GetModuleFileNameW(nullptr, path, MAX_PATH);
  std::wstring directory = path;
  return directory.substr(0, directory.find_last_of(L'\\'));
}

// The install location recorded by the installer; empty for a portable copy.
std::wstring InstalledDirectory() {
  wchar_t value[MAX_PATH];
  DWORD size = sizeof(value);
  if (RegGetValueW(HKEY_CURRENT_USER, kUninstallKey, L"InstallLocation",
                   RRF_RT_REG_SZ, nullptr, value, &size) != ERROR_SUCCESS) {
    return L"";
  }
  return value;
}

// Copies this program, with the engine and C runtime of the app beside it
// and its own Dart files in "setup", to a temporary directory, and runs the
// copy there on [app_dir] so that the install directory can be deleted.
int RelaunchFromTemp(const std::wstring& app_dir) {
  wchar_t temp[MAX_PATH], self[MAX_PATH];
  GetTempPathW(MAX_PATH, temp);
  GetModuleFileNameW(nullptr, self, MAX_PATH);
  const std::wstring copy = std::wstring(temp) + L"melonbang-uninstall-" +
                            std::to_wstring(GetTickCount64());
  if (!CreateDirectoryW(copy.c_str(), nullptr) ||
      !CopyFileW(self, (copy + L"\\uninstall.exe").c_str(), FALSE)) {
    return 1;
  }
  for (const wchar_t* name : {L"flutter_windows.dll", L"msvcp140.dll",
                              L"vcruntime140.dll", L"vcruntime140_1.dll"}) {
    if (!CopyFileW((app_dir + L"\\" + name).c_str(),
                   (copy + L"\\" + name).c_str(), FALSE)) {
      return 1;
    }
  }
  // SHFileOperation needs double-NUL-terminated lists.
  const std::wstring from = app_dir + L"\\setup" + L'\0';
  const std::wstring to = copy + L'\0';
  SHFILEOPSTRUCTW operation{};
  operation.wFunc = FO_COPY;
  operation.pFrom = from.c_str();
  operation.pTo = to.c_str();
  operation.fFlags = FOF_NO_UI;
  if (SHFileOperationW(&operation) != 0) return 1;

  std::wstring command =
      L"\"" + copy + L"\\uninstall.exe\" --uninstall \"" + app_dir + L"\"";
  STARTUPINFOW startup{sizeof(startup)};
  PROCESS_INFORMATION process{};
  if (!CreateProcessW(nullptr, command.data(), nullptr, nullptr, FALSE, 0,
                      nullptr, copy.c_str(), &startup, &process)) {
    return 1;
  }
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return 0;
}

// Deletes [directory], this temporary copy, once the process has exited.
void RemoveLater(const std::wstring& directory) {
  std::wstring command =
      L"cmd.exe /c ping 127.0.0.1 -n 3 > nul & rmdir /s /q \"" + directory +
      L"\"";
  // Started outside it: a directory cannot be removed while it is a
  // process's current directory.
  const std::wstring parent = directory.substr(0, directory.find_last_of(L'\\'));
  STARTUPINFOW startup{sizeof(startup)};
  PROCESS_INFORMATION process{};
  if (CreateProcessW(nullptr, command.data(), nullptr, nullptr, FALSE,
                     CREATE_NO_WINDOW, nullptr, parent.c_str(), &startup,
                     &process)) {
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
  }
}

}  // namespace

// The same program installs and uninstalls:
//   melonbang_setup.exe --payload <zip>   from the bootstrapper
//   uninstall.exe                         in an install directory
//   uninstall.exe --uninstall <dir>       the temporary copy that removes it
int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  const auto has = [&](const char* name) {
    return std::find(command_line_arguments.begin(),
                     command_line_arguments.end(),
                     name) != command_line_arguments.end();
  };
  const bool uninstalling = has("--uninstall");
  if (!uninstalling && !has("--payload")) {
    const std::wstring here = ModuleDirectory();
    // Only a directory the installer created is deleted as a whole; a
    // portable copy may share its folder with unrelated files.
    if (CompareStringOrdinal(InstalledDirectory().c_str(), -1, here.c_str(),
                             -1, TRUE) != CSTR_EQUAL) {
      MessageBoxW(nullptr,
                  L"这是便携版 MelonBanG，不需要卸载，直接删除文件夹即可。",
                  L"卸载 MelonBanG", MB_ICONINFORMATION);
      return EXIT_SUCCESS;
    }
    return RelaunchFromTemp(here);
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Beside the program, whose own Dart files are in "data", the
  // uninstaller's are in "setup".
  flutter::DartProject project(uninstalling ? L"setup" : L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // Centered on the primary work area; sizes are in logical pixels.
  RECT work;
  SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
  const double scale = GetDpiForSystem() / 96.0;
  Win32Window::Size size(760, 480);
  Win32Window::Point origin(
      static_cast<unsigned int>(
          (work.left + (work.right - work.left) / 2) / scale - size.width / 2),
      static_cast<unsigned int>(
          (work.top + (work.bottom - work.top) / 2) / scale - size.height / 2));
  if (!window.Create(uninstalling ? L"卸载 MelonBanG" : L"安装 MelonBanG",
                     origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (uninstalling) RemoveLater(ModuleDirectory());
  return EXIT_SUCCESS;
}
