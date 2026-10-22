// Swaps a prepared update into the install directory after MelonBanG exits.
//
//   updater.exe --pid <pid> --app-dir <dir> --staging <dir> --version <v> [--restart]
//
// The app has already downloaded, verified and extracted the new version into
// <staging> inside <app-dir>\.pending, so the swap is a few renames on one
// volume. Each top-level entry of <staging> replaces the entry of the same
// name; any failed rename rolls the swapped entries back, so the install is
// never left half old and half new. The app copies this program to a
// temporary directory before running it, which lets it replace itself.
#include <windows.h>
#include <shellapi.h>

#include <string>
#include <vector>

namespace {

constexpr wchar_t kTitle[] = L"MelonBanG 更新";
constexpr wchar_t kUninstallKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\MelonBanG";

struct Options {
  DWORD pid = 0;
  std::wstring app_dir, staging, version;
  bool restart = false;
};

std::wstring Join(const std::wstring& directory, const std::wstring& name) {
  return directory + L"\\" + name;
}

std::wstring SystemMessage(DWORD error) {
  wchar_t* buffer = nullptr;
  FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
                     FORMAT_MESSAGE_IGNORE_INSERTS,
                 nullptr, error, 0, reinterpret_cast<wchar_t*>(&buffer), 0,
                 nullptr);
  std::wstring message = buffer ? buffer : L"未知错误";
  LocalFree(buffer);
  return message;
}

std::vector<std::wstring> Entries(const std::wstring& directory) {
  std::vector<std::wstring> names;
  WIN32_FIND_DATAW data;
  HANDLE find = FindFirstFileW(Join(directory, L"*").c_str(), &data);
  if (find == INVALID_HANDLE_VALUE) return names;
  do {
    std::wstring name = data.cFileName;
    if (name != L"." && name != L"..") names.push_back(name);
  } while (FindNextFileW(find, &data));
  FindClose(find);
  return names;
}

bool Exists(const std::wstring& path) {
  return GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES;
}

void RemoveTree(const std::wstring& path) {
  // SHFileOperation needs a double-NUL-terminated list.
  std::wstring from = path + L'\0';
  SHFILEOPSTRUCTW operation{};
  operation.wFunc = FO_DELETE;
  operation.pFrom = from.c_str();
  operation.fFlags = FOF_NO_UI;
  SHFileOperationW(&operation);
}

struct Move {
  std::wstring from, to;
};

// Moves every staged entry into place, recording each rename so a failure can
// undo them in reverse order. Returns 0 on success or the failing error.
DWORD Swap(const Options& options, const std::wstring& backup,
           const std::vector<std::wstring>& names) {
  std::vector<Move> done;
  auto rename = [&](const std::wstring& from, const std::wstring& to) {
    if (!MoveFileExW(from.c_str(), to.c_str(), 0)) return false;
    done.push_back({from, to});
    return true;
  };
  for (const auto& name : names) {
    const std::wstring current = Join(options.app_dir, name);
    if ((Exists(current) && !rename(current, Join(backup, name))) ||
        !rename(Join(options.staging, name), current)) {
      const DWORD error = GetLastError();
      for (auto it = done.rbegin(); it != done.rend(); ++it) {
        MoveFileExW(it->to.c_str(), it->from.c_str(), 0);
      }
      return error;
    }
  }
  return 0;
}

void RecordVersion(const std::wstring& version) {
  HKEY key;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kUninstallKey, 0, KEY_SET_VALUE,
                    &key) != ERROR_SUCCESS) {
    return;  // A portable copy has no uninstall entry.
  }
  RegSetValueExW(key, L"DisplayVersion", 0, REG_SZ,
                 reinterpret_cast<const BYTE*>(version.c_str()),
                 static_cast<DWORD>((version.size() + 1) * sizeof(wchar_t)));
  RegCloseKey(key);
}

void Launch(const std::wstring& app_dir) {
  std::wstring command = L"\"" + Join(app_dir, L"melonbang.exe") + L"\"";
  STARTUPINFOW startup{sizeof(startup)};
  PROCESS_INFORMATION process{};
  if (CreateProcessW(nullptr, command.data(), nullptr, nullptr, FALSE, 0,
                     nullptr, app_dir.c_str(), &startup, &process)) {
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
  }
}

bool Parse(Options& options) {
  int count = 0;
  wchar_t** arguments = CommandLineToArgvW(GetCommandLineW(), &count);
  for (int i = 1; i < count; i++) {
    const std::wstring name = arguments[i];
    const bool has_value = i + 1 < count;
    if (name == L"--restart") {
      options.restart = true;
    } else if (name == L"--pid" && has_value) {
      options.pid = wcstoul(arguments[++i], nullptr, 10);
    } else if (name == L"--app-dir" && has_value) {
      options.app_dir = arguments[++i];
    } else if (name == L"--staging" && has_value) {
      options.staging = arguments[++i];
    } else if (name == L"--version" && has_value) {
      options.version = arguments[++i];
    }
  }
  LocalFree(arguments);
  return options.pid != 0 && !options.app_dir.empty() &&
         !options.staging.empty() && !options.version.empty();
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE, _In_opt_ HINSTANCE, _In_ wchar_t*,
                      _In_ int) {
  Options options;
  if (!Parse(options)) {
    MessageBoxW(nullptr, L"更新参数不完整。", kTitle, MB_ICONERROR);
    return 2;
  }
  if (HANDLE app = OpenProcess(SYNCHRONIZE, FALSE, options.pid)) {
    const DWORD waited = WaitForSingleObject(app, 60000);
    CloseHandle(app);
    if (waited != WAIT_OBJECT_0) {
      MessageBoxW(nullptr, L"MelonBanG 没有退出，更新已取消，下次退出时会再试。",
                  kTitle, MB_ICONWARNING);
      return 1;
    }
  }

  const std::wstring pending = Join(options.app_dir, L".pending");
  const std::wstring backup = Join(pending, L"backup");
  RemoveTree(backup);
  CreateDirectoryW(backup.c_str(), nullptr);
  const auto names = Entries(options.staging);

  // Antivirus scans and handles released just after exit can block a rename
  // briefly; each attempt is fully rolled back before the next.
  DWORD error = 0;
  for (int attempt = 0; attempt < 20; attempt++) {
    error = Swap(options, backup, names);
    if (error == 0) break;
    Sleep(500);
  }
  if (error != 0) {
    const std::wstring message = L"无法替换程序文件，已保留当前版本。\n\n" +
                                 SystemMessage(error) +
                                 L"\n下次退出 MelonBanG 时会再试。";
    MessageBoxW(nullptr, message.c_str(), kTitle, MB_ICONWARNING);
  } else {
    RecordVersion(options.version);
    RemoveTree(pending);
  }
  if (options.restart) Launch(options.app_dir);
  return error == 0 ? 0 : 1;
}
