// Removes an installed MelonBanG: program files, shortcuts and the entry in
// Windows' installed apps. Application data and downloaded media stay where
// the app keeps them, outside the install directory.
//
// Started from the install directory, it copies itself to a temporary
// directory and runs from there so that it can delete the install directory.
#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <tlhelp32.h>

#include <string>

namespace {

constexpr wchar_t kTitle[] = L"卸载 MelonBanG";
constexpr wchar_t kUninstallKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\MelonBanG";

std::wstring ModuleDirectory() {
  wchar_t path[MAX_PATH];
  GetModuleFileNameW(nullptr, path, MAX_PATH);
  std::wstring directory = path;
  return directory.substr(0, directory.find_last_of(L'\\'));
}

std::wstring KnownFolder(REFKNOWNFOLDERID id) {
  wchar_t* path = nullptr;
  SHGetKnownFolderPath(id, 0, nullptr, &path);
  std::wstring result = path;
  CoTaskMemFree(path);
  return result;
}

bool SamePath(const std::wstring& a, const std::wstring& b) {
  return CompareStringOrdinal(a.c_str(), -1, b.c_str(), -1, TRUE) ==
         CSTR_EQUAL;
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

// Whether any process runs an executable from inside [directory]: the app,
// or anything it started from there. A running image can still be opened for
// reading, so the process list is the reliable check.
bool RunningIn(std::wstring directory) {
  while (!directory.empty() && directory.back() == L'\\') directory.pop_back();
  const std::wstring prefix = directory + L"\\";
  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  PROCESSENTRY32W entry{sizeof(entry)};
  bool found = false;
  for (BOOL more = Process32FirstW(snapshot, &entry); more && !found;
       more = Process32NextW(snapshot, &entry)) {
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                                 entry.th32ProcessID);
    if (!process) continue;
    wchar_t path[MAX_PATH];
    DWORD size = MAX_PATH;
    found = QueryFullProcessImageNameW(process, 0, path, &size) &&
            size > prefix.size() &&
            CompareStringOrdinal(path, static_cast<int>(prefix.size()),
                                 prefix.c_str(),
                                 static_cast<int>(prefix.size()),
                                 TRUE) == CSTR_EQUAL;
    CloseHandle(process);
  }
  CloseHandle(snapshot);
  return found;
}

bool RemoveTree(const std::wstring& path) {
  std::wstring from = path + L'\0';
  SHFILEOPSTRUCTW operation{};
  operation.wFunc = FO_DELETE;
  operation.pFrom = from.c_str();
  operation.fFlags = FOF_NO_UI;
  return SHFileOperationW(&operation) == 0;
}

int RelaunchFromTemp(const std::wstring& app_dir) {
  wchar_t temp[MAX_PATH], self[MAX_PATH];
  GetTempPathW(MAX_PATH, temp);
  GetModuleFileNameW(nullptr, self, MAX_PATH);
  const std::wstring copy = std::wstring(temp) + L"melonbang-uninstall-" +
                            std::to_wstring(GetTickCount64()) + L".exe";
  if (!CopyFileW(self, copy.c_str(), FALSE)) return 1;
  std::wstring command = L"\"" + copy + L"\" --app-dir \"" + app_dir + L"\"";
  STARTUPINFOW startup{sizeof(startup)};
  PROCESS_INFORMATION process{};
  if (!CreateProcessW(nullptr, command.data(), nullptr, nullptr, FALSE, 0,
                      nullptr, temp, &startup, &process)) {
    return 1;
  }
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return 0;
}

// Deletes this temporary copy once it has exited.
void DeleteSelfLater() {
  wchar_t self[MAX_PATH];
  GetModuleFileNameW(nullptr, self, MAX_PATH);
  std::wstring command = L"cmd.exe /c ping 127.0.0.1 -n 3 > nul & del \"" +
                         std::wstring(self) + L"\"";
  STARTUPINFOW startup{sizeof(startup)};
  PROCESS_INFORMATION process{};
  if (CreateProcessW(nullptr, command.data(), nullptr, nullptr, FALSE,
                     CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process)) {
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
  }
}

int Uninstall(const std::wstring& app_dir) {
  if (MessageBoxW(nullptr,
                  L"确定要卸载 MelonBanG 吗？\n\n追番记录、设置和已下载的媒体会保留，"
                  L"重新安装后可以继续使用。",
                  kTitle, MB_ICONQUESTION | MB_YESNO) != IDYES) {
    return 0;
  }
  while (RunningIn(app_dir)) {
    if (MessageBoxW(nullptr, L"MelonBanG 正在运行，请先关闭它再继续。", kTitle,
                    MB_ICONWARNING | MB_RETRYCANCEL) != IDRETRY) {
      return 0;
    }
  }
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  DeleteFileW((KnownFolder(FOLDERID_Desktop) + L"\\MelonBanG.lnk").c_str());
  DeleteFileW((KnownFolder(FOLDERID_Programs) + L"\\MelonBanG.lnk").c_str());
  CoUninitialize();
  RegDeleteTreeW(HKEY_CURRENT_USER, kUninstallKey);
  if (!RemoveTree(app_dir)) {
    const std::wstring message =
        L"部分程序文件未能删除，可以手动删除这个文件夹：\n" + app_dir;
    MessageBoxW(nullptr, message.c_str(), kTitle, MB_ICONWARNING);
  } else {
    MessageBoxW(nullptr, L"MelonBanG 已卸载。", kTitle, MB_ICONINFORMATION);
  }
  return 0;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE, _In_opt_ HINSTANCE, _In_ wchar_t*,
                      _In_ int) {
  int count = 0;
  wchar_t** arguments = CommandLineToArgvW(GetCommandLineW(), &count);
  std::wstring app_dir;
  for (int i = 1; i + 1 < count; i++) {
    if (std::wstring(arguments[i]) == L"--app-dir") app_dir = arguments[i + 1];
  }
  LocalFree(arguments);
  if (app_dir.empty()) {
    const std::wstring here = ModuleDirectory();
    // Only a directory the installer created is deleted as a whole; a
    // portable copy may share its folder with unrelated files.
    if (!SamePath(InstalledDirectory(), here)) {
      MessageBoxW(nullptr,
                  L"这是便携版 MelonBanG，不需要卸载，直接删除文件夹即可。",
                  kTitle, MB_ICONINFORMATION);
      return 0;
    }
    return RelaunchFromTemp(here);
  }
  const int result = Uninstall(app_dir);
  DeleteSelfLater();
  return result;
}
