#include "setup_channel.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <tlhelp32.h>

#include <memory>
#include <optional>
#include <string>

#include "utils.h"

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr wchar_t kUninstallKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\MelonBanG";

std::wstring Wide(const std::string& text) {
  if (text.empty()) return L"";
  const int length = MultiByteToWideChar(CP_UTF8, 0, text.data(),
                                         static_cast<int>(text.size()),
                                         nullptr, 0);
  std::wstring result(length, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      result.data(), length);
  return result;
}

std::string Narrow(const wchar_t* text) { return Utf8FromUtf16(text); }

std::string Argument(const EncodableMap& arguments, const char* name) {
  return std::get<std::string>(arguments.at(EncodableValue(name)));
}

std::string KnownFolder(REFKNOWNFOLDERID id) {
  wchar_t* path = nullptr;
  SHGetKnownFolderPath(id, 0, nullptr, &path);
  std::string result = Narrow(path);
  CoTaskMemFree(path);
  return result;
}

std::optional<std::string> InstalledLocation() {
  wchar_t value[MAX_PATH];
  DWORD size = sizeof(value);
  if (RegGetValueW(HKEY_CURRENT_USER, kUninstallKey, L"InstallLocation",
                   RRF_RT_REG_SZ, nullptr, value, &size) != ERROR_SUCCESS) {
    return std::nullopt;
  }
  return Narrow(value);
}

std::optional<std::string> PickFolder(HWND owner, const std::wstring& initial) {
  IFileOpenDialog* dialog = nullptr;
  if (FAILED(CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_ALL,
                              IID_PPV_ARGS(&dialog)))) {
    return std::nullopt;
  }
  FILEOPENDIALOGOPTIONS options;
  dialog->GetOptions(&options);
  dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM);
  dialog->SetTitle(L"选择安装位置");
  IShellItem* folder = nullptr;
  if (SUCCEEDED(SHCreateItemFromParsingName(initial.c_str(), nullptr,
                                            IID_PPV_ARGS(&folder)))) {
    dialog->SetFolder(folder);
    folder->Release();
  }
  std::optional<std::string> result;
  IShellItem* item = nullptr;
  if (SUCCEEDED(dialog->Show(owner)) && SUCCEEDED(dialog->GetResult(&item))) {
    wchar_t* path = nullptr;
    if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path))) {
      result = Narrow(path);
      CoTaskMemFree(path);
    }
    item->Release();
  }
  dialog->Release();
  return result;
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

HRESULT CreateShortcut(const std::wstring& link, const std::wstring& target,
                       const std::wstring& directory) {
  IShellLinkW* shortcut = nullptr;
  HRESULT result = CoCreateInstance(CLSID_ShellLink, nullptr,
                                    CLSCTX_INPROC_SERVER,
                                    IID_PPV_ARGS(&shortcut));
  if (FAILED(result)) return result;
  shortcut->SetPath(target.c_str());
  shortcut->SetWorkingDirectory(directory.c_str());
  shortcut->SetIconLocation(target.c_str(), 0);
  IPersistFile* file = nullptr;
  result = shortcut->QueryInterface(IID_PPV_ARGS(&file));
  if (SUCCEEDED(result)) {
    result = file->Save(link.c_str(), TRUE);
    file->Release();
  }
  shortcut->Release();
  return result;
}

LSTATUS Register(const std::wstring& location, const std::wstring& version,
                 DWORD size_kb) {
  HKEY key;
  LSTATUS status =
      RegCreateKeyExW(HKEY_CURRENT_USER, kUninstallKey, 0, nullptr, 0,
                      KEY_SET_VALUE, nullptr, &key, nullptr);
  if (status != ERROR_SUCCESS) return status;
  const auto text = [&](const wchar_t* name, const std::wstring& value) {
    RegSetValueExW(key, name, 0, REG_SZ,
                   reinterpret_cast<const BYTE*>(value.c_str()),
                   static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
  };
  const auto number = [&](const wchar_t* name, DWORD value) {
    RegSetValueExW(key, name, 0, REG_DWORD,
                   reinterpret_cast<const BYTE*>(&value), sizeof(value));
  };
  const std::wstring uninstall = L"\"" + location + L"\\uninstall.exe\"";
  text(L"DisplayName", L"MelonBanG");
  text(L"DisplayVersion", version);
  text(L"Publisher", L"MelonBanG");
  text(L"URLInfoAbout", L"https://github.com/shirumesu/MelonBanG");
  text(L"InstallLocation", location);
  text(L"DisplayIcon", location + L"\\melonbang.exe");
  text(L"UninstallString", uninstall);
  text(L"QuietUninstallString", uninstall);
  number(L"EstimatedSize", size_kb);
  number(L"NoModify", 1);
  number(L"NoRepair", 1);
  RegCloseKey(key);
  return ERROR_SUCCESS;
}

}  // namespace

void RegisterSetupChannel(flutter::BinaryMessenger* messenger, HWND window) {
  // The channel lives as long as the engine, which outlives every call.
  static std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;
  channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "melonbang/setup",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([window](const auto& call, auto result) {
    const std::string& method = call.method_name();
    const auto* arguments = std::get_if<EncodableMap>(call.arguments());
    if (method == "folders") {
      result->Success(EncodableMap{
          {EncodableValue("localAppData"),
           EncodableValue(KnownFolder(FOLDERID_LocalAppData))},
          {EncodableValue("desktop"),
           EncodableValue(KnownFolder(FOLDERID_Desktop))},
          {EncodableValue("programs"),
           EncodableValue(KnownFolder(FOLDERID_Programs))},
      });
    } else if (method == "installedLocation") {
      const auto location = InstalledLocation();
      result->Success(location ? EncodableValue(*location) : EncodableValue());
    } else if (method == "pickFolder") {
      const auto folder =
          PickFolder(window, Wide(Argument(*arguments, "initial")));
      result->Success(folder ? EncodableValue(*folder) : EncodableValue());
    } else if (method == "isRunning") {
      result->Success(
          EncodableValue(RunningIn(Wide(Argument(*arguments, "directory")))));
    } else if (method == "createShortcut") {
      const HRESULT created = CreateShortcut(
          Wide(Argument(*arguments, "link")),
          Wide(Argument(*arguments, "target")),
          Wide(Argument(*arguments, "directory")));
      if (SUCCEEDED(created)) {
        result->Success();
      } else {
        result->Error("shortcut", "无法创建快捷方式",
                      EncodableValue(static_cast<int>(created)));
      }
    } else if (method == "register") {
      const LSTATUS status = Register(
          Wide(Argument(*arguments, "location")),
          Wide(Argument(*arguments, "version")),
          static_cast<DWORD>(
              std::get<int>(arguments->at(EncodableValue("sizeKb")))));
      if (status == ERROR_SUCCESS) {
        result->Success();
      } else {
        result->Error("register", "无法写入已安装应用列表",
                      EncodableValue(static_cast<int>(status)));
      }
    } else if (method == "open") {
      ShellExecuteW(window, L"open", Wide(Argument(*arguments, "target")).c_str(),
                    nullptr, nullptr, SW_SHOWNORMAL);
      result->Success();
    } else if (method == "startDrag") {
      ReleaseCapture();
      SendMessage(window, WM_NCLBUTTONDOWN, HTCAPTION, 0);
      result->Success();
    } else if (method == "minimize") {
      ShowWindow(window, SW_MINIMIZE);
      result->Success();
    } else if (method == "close") {
      PostMessage(window, WM_CLOSE, 0, 0);
      result->Success();
    } else {
      result->NotImplemented();
    }
  });
}
