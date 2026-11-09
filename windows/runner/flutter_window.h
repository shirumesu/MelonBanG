#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <cstdint>
#include <memory>
#include <optional>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
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
  // Lets Dart save what the downloads need to resume and close the database
  // while Windows ends the session, waiting a few seconds at most.
  void EndSession();

  // Shows a notification about a cached episode as a balloon, which Windows
  // 10 and later show as a toast, from a notification icon of the runner's
  // own that goes away with the balloon.
  void ShowNotification(const flutter::EncodableMap& arguments);
  void RemoveNotificationIcon();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Takes Dart's request to quit once its services are closed.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      system_channel_;

  // Whether the notification icon is shown, and the show its balloon is
  // about, opened on a click.
  bool notification_icon_ = false;
  std::optional<int64_t> notification_subject_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
