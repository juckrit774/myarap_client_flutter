import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {

  // Shared channel so AppDelegate can invoke Flutter methods
  static var windowChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let messenger = flutterViewController.engine.binaryMessenger

    // Device info channel (Flutter → Swift)
    let deviceChannel = FlutterMethodChannel(name: "com.myarap/device_info", binaryMessenger: messenger)
    deviceChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "getDeviceInfo":
        MacDeviceInfo.collect(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Window control channel (Swift → Flutter)
    MainFlutterWindow.windowChannel = FlutterMethodChannel(name: "com.myarap/window", binaryMessenger: messenger)

    super.awakeFromNib()
  }

  // Hide window instead of closing (red ✕ button)
  override func close() {
    orderOut(nil)
    NSApp.setActivationPolicy(.accessory)
  }

  // Hide window instead of minimizing (yellow − button)
  override func miniaturize(_ sender: Any?) {
    orderOut(nil)
    NSApp.setActivationPolicy(.accessory)
  }
}
