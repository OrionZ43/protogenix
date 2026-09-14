#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shellapi.h>
#include <wchar.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

#ifndef _DEBUG
namespace {

// Single-instance guard. The name must match AppMutexName in
// windows/installer/protogenix.iss: the installer waits for this mutex to
// disappear before replacing files. Disabled in debug builds so that
// `flutter run` works next to an installed copy.
constexpr wchar_t kSingleInstanceMutex[] =
    L"Z43Studios.Protogenix.SingleInstance";

// Hands a protogenix:// link from this launch's command line to the running
// copy: the browser starts a new process for every link, but the app keeps a
// single window (lib/features/listen/presentation/listen_links.dart).
void ForwardListenLink(HWND window) {
  int argc = 0;
  LPWSTR* argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return;
  }
  for (int i = 1; i < argc; i++) {
    if (::_wcsnicmp(argv[i], L"protogenix:", 11) != 0) {
      continue;
    }
    std::string link = Utf8FromUtf16(argv[i]);
    if (!link.empty()) {
      COPYDATASTRUCT data{};
      data.dwData = kListenLinkCopyDataId;
      data.cbData = static_cast<DWORD>(link.size());
      data.lpData = link.data();
      ::SendMessageW(window, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&data));
    }
    break;
  }
  ::LocalFree(argv);
}

// Brings the already running Protogenix window to the front and hands it the
// link this launch was started with, if any.
void ActivateExistingWindow() {
  HWND window = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"Protogenix");
  if (window == nullptr) {
    return;
  }
  ForwardListenLink(window);
  if (::IsIconic(window)) {
    ::ShowWindow(window, SW_RESTORE);
  }
  ::SetForegroundWindow(window);
}

}  // namespace
#endif

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
#ifndef _DEBUG
  HANDLE instance_mutex = ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutex);
  if (instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    ActivateExistingWindow();
    ::CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
  }
#endif

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
  if (!window.Create(L"Protogenix", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
#ifndef _DEBUG
  if (instance_mutex != nullptr) {
    ::CloseHandle(instance_mutex);
  }
#endif
  return EXIT_SUCCESS;
}
