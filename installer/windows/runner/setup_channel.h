#ifndef RUNNER_SETUP_CHANNEL_H_
#define RUNNER_SETUP_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

// Windows operations the installer UI needs: known folders, the folder
// picker, shortcuts, the installed-apps entry, opening links and moving the
// frameless window.
void RegisterSetupChannel(flutter::BinaryMessenger* messenger, HWND window);

#endif  // RUNNER_SETUP_CHANNEL_H_
