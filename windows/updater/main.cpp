// Swaps a prepared update into the install directory after MelonBanG exits.
//
//   updater.exe --pid <pid> --app-dir <dir> --staging <dir> --version <v> [--restart]
//
// The app has already downloaded, verified and extracted the new version into
// <staging> inside <app-dir>\.pending, so the swap is a few renames on one
// volume. Each top-level entry of <staging> replaces the entry of the same
// name; any failed rename rolls the swapped entries back, so the install is
// not left half old and half new. Should a rollback rename stay blocked, the
// old entries it could not put back stay in <app-dir>\.pending\backup, which
// later runs leave alone, and reinstalling repairs the install. The app
// copies this program to a temporary directory before running it, which lets
// it replace itself.
#include <windows.h>
#include <shellapi.h>

#include <string>
#include <vector>

namespace {

constexpr wchar_t kTitle[] = L"MelonBanG 更新";
constexpr wchar_t kUninstallKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\MelonBanG";

// Antivirus scans and handles released just after exit can block a rename
// briefly, so renames are tried this many times, this far apart.
constexpr int kAttempts = 20;
constexpr DWORD kRetryDelay = 500;

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

// Puts back the renames in [done], newest first. The locks that failed the
// swap can hold the entries just moved as well, so each is tried several
// times. Returns false once one stays blocked, leaving the older renames as
// they are, since a name's two renames only undo in order.
bool Undo(const std::vector<Move>& done) {
  for (auto it = done.rbegin(); it != done.rend(); ++it) {
    bool moved = false;
    for (int attempt = 0; attempt < kAttempts && !moved; attempt++) {
      if (attempt > 0) Sleep(kRetryDelay);
      moved = MoveFileExW(it->to.c_str(), it->from.c_str(), 0) != 0;
    }
    if (!moved) return false;
  }
  return true;
}

struct SwapResult {
  // 0 on success, otherwise the error of the rename that failed.
  DWORD error = 0;
  // Whether a failed swap put back every entry it had moved.
  bool restored = true;
};

// Moves every staged entry into place, recording each rename so a failure can
// undo them in reverse order.
SwapResult Swap(const Options& options, const std::wstring& backup,
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
      return {error, Undo(done)};
    }
  }
  return {};
}

// Updates the installed apps entry when it belongs to [app_dir]; a portable
// copy updated beside an installed one leaves that entry alone.
void RecordVersion(const std::wstring& app_dir, const std::wstring& version) {
  wchar_t location[MAX_PATH];
  DWORD size = sizeof(location);
  if (RegGetValueW(HKEY_CURRENT_USER, kUninstallKey, L"InstallLocation",
                   RRF_RT_REG_SZ, nullptr, location, &size) != ERROR_SUCCESS ||
      CompareStringOrdinal(location, -1, app_dir.c_str(), -1, TRUE) !=
          CSTR_EQUAL) {
    return;
  }
  HKEY key;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kUninstallKey, 0, KEY_SET_VALUE,
                    &key) != ERROR_SUCCESS) {
    return;
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
  const std::wstring repair =
      L"\n请重新运行 MelonBanG 安装程序修复，原来的文件保存在 " + backup +
      L"。";
  // A full rollback leaves the backup empty; entries still in it are the
  // only copy of what an earlier swap could not put back.
  if (!Entries(backup).empty()) {
    const std::wstring message =
        L"上次更新没能换回全部程序文件，MelonBanG 可能无法正常运行，"
        L"更新已停止。\n" +
        repair;
    MessageBoxW(nullptr, message.c_str(), kTitle, MB_ICONERROR);
    return 1;
  }
  CreateDirectoryW(backup.c_str(), nullptr);
  const auto names = Entries(options.staging);

  // Each failed attempt is rolled back before the next; one that cannot be
  // ends the attempts, since the install is then no longer the old one.
  SwapResult result;
  for (int attempt = 0; attempt < kAttempts; attempt++) {
    result = Swap(options, backup, names);
    if (result.error == 0 || !result.restored) break;
    Sleep(kRetryDelay);
  }
  if (!result.restored) {
    const std::wstring message =
        L"无法替换程序文件，也没能换回全部已替换的文件，MelonBanG "
        L"可能无法正常运行。\n\n" +
        SystemMessage(result.error) + repair;
    MessageBoxW(nullptr, message.c_str(), kTitle, MB_ICONERROR);
    return 1;
  }
  if (result.error != 0) {
    const std::wstring message = L"无法替换程序文件，已保留当前版本。\n\n" +
                                 SystemMessage(result.error) +
                                 L"\n下次退出 MelonBanG 时会再试。";
    MessageBoxW(nullptr, message.c_str(), kTitle, MB_ICONWARNING);
  } else {
    RecordVersion(options.app_dir, options.version);
    RemoveTree(pending);
  }
  if (options.restart) Launch(options.app_dir);
  return result.error == 0 ? 0 : 1;
}
