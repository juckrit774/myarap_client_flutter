# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Install dependencies
flutter pub get

# Run on macOS
flutter run -d macos

# Run on Windows
flutter run -d windows

# Lint / static analysis
flutter analyze

# Run tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Release build (Windows)
flutter build windows --release
# Output: build/windows/x64/runner/Release/
```

## Windows Installer Builds

Two installer formats are built in CI (GitHub Actions, also GitLab CI):

**EXE (Inno Setup)**
```powershell
choco install innosetup -y
iscc installer\setup.iss
# Output: installer\installer_output\MyARAP_Setup.exe
```

**MSI (WiX v4)**
```powershell
dotnet tool install --global wix
wix build installer\product.wxs -o installer\installer_output\MyARAP.msi -d SourceDir=build\windows\x64\runner\Release
```

CI triggers on push to `develop`, `main`, `master`. Artifacts are uploaded to GitHub Actions and kept 30 days.

## Architecture

MYARAP is a **desktop IT-asset management client** for macOS and Windows. It auto-authenticates using the machine's hardware identity (no user login form), reports device info to a backend server, and lets users submit and view IT problems.

### Folder layout

```
lib/
  core/
    config/        # AppConfig (baseUrl, version), AppColors
    models/        # BaseRequestModel, BaseResponseModel<T>
    services/      # NetworkManager singleton
    storage/       # CacheManager (SharedPreferences)
  features/
    auth/          # LoginResponseModel only (no screen — auto-auth)
    home/          # Dashboard: device info display + authentication heartbeat
    notification/  # Notification list/detail (currently mock data)
    problem/       # View submitted IT problems from the server
    report/        # Submit a new IT problem with optional images
    qrcode/        # Display token as QR code dialog
    settings/      # Runtime server URL config + cache clear
  shared/widgets/  # AppHeader, LoadingOverlay
installer/         # setup.iss (Inno Setup EXE), product.wxs (WiX MSI)
macos/             # macOS native runner (Swift MethodChannel handlers)
windows/           # Windows native runner (C++ MethodChannel handlers)
```

### API envelope pattern

Every API call uses a fixed JSON envelope through `NetworkManager` (Dio singleton):

**Request** (`BaseRequestModel`):
```json
{ "module": "...", "target": "...", "token": "...", "data": {...}, "APIVersion": "1.0.1" }
```

**Response** (`BaseResponseModel<T>`):
```json
{ "status": 200, "message": "...", "entries": ... }
```
`isSuccess` = `status == 200`. A `status == 401` triggers `NetworkManager.onUnauthorized`, which clears the cache and navigates back to HomeScreen.

The three server endpoints used:
| Endpoint | Purpose |
|---|---|
| `/v2/api/AssetAuthen` | Auto-login (default, no explicit `url`) |
| `/v2/api/Select` | Read data (problems, problem types) |
| `/v2/api/Insert` | Create a problem report |
| `/v2/api/Upload` | Multipart image upload |

### State management

All screens use `provider` with `ChangeNotifier` ViewModels:
- `ChangeNotifierProvider` is created at the screen level (not app-level)
- ViewModels expose `isLoading`, `errorMessage`, and domain state; screens call `context.watch<VM>()` / `context.read<VM>()`
- When an API call fails, ViewModels fall back to `mockList()` data rather than showing an error (exception: `ProblemViewModel` shows an error string)

### Authentication flow

On launch, `HomeViewModel.initialize()`:
1. Loads cached `LoginResponseModel` from SharedPreferences
2. Collects hardware device info (`DeviceDetail.collect()`)
3. Posts to `AssetAuthen` with device fingerprint — no user credentials
4. On success: caches the new `LoginResponseModel`, then calls `UpdateDeviceInfo` to register the device online
5. On failure: uses the cached login if available, or synthesises a minimal offline fallback object
6. Schedules a heartbeat (`UpdateDeviceInfo`) using the `dueDateTime` unix timestamp returned by the server

### Device info collection

- **macOS**: via `MethodChannel('com.myarap/device_info')` → `getDeviceInfo` (implemented in Swift native runner)
- **Windows**: inline PowerShell script executed via `Process.run('powershell', ...)` — collects WMI data and installed software from the registry
- Falls back to a zeroed-out `DeviceDetail` if collection fails

### Platform-specific native channels

| Channel | Platform | Method | Purpose |
|---|---|---|---|
| `com.myarap/device_info` | macOS, Windows | `getDeviceInfo` | Hardware/OS info |
| `com.myarap/window` | macOS only | `openSetting` | macOS menu bar → Settings screen |

### Server URL configuration

The backend URL defaults to `https://localhost:8000` (`AppConfig.baseUrl`). Users can change it at runtime in **Settings** → stored in SharedPreferences as `server_url` → picked up by `NetworkManager.updateBaseUrl()` on next launch (or immediately after saving).

SSL certificate validation is **disabled** (`badCertificateCallback = true`) because the server uses a self-signed cert.
