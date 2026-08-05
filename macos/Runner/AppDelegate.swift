import Cocoa
import FlutterMacOS
import IOKit
import Metal

@main
class AppDelegate: FlutterAppDelegate {
  // Static so it's retained at class level — NSStatusBar does NOT retain status items.
  private static var statusItem: NSStatusItem!

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false  // Keep running in menu bar after window is hidden
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  @objc override func applicationWillFinishLaunching(_ notification: Notification) {
    super.applicationWillFinishLaunching(notification)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      self.setupStatusBar()
    }
  }

  // Re-show window when user clicks the dock icon while window is hidden
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag { showMainWindow() }
    return true
  }

  // MARK: - Status Bar

  private func setupStatusBar() {
    AppDelegate.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    guard let button = AppDelegate.statusItem.button else { return }

    if let url = Bundle.main.url(forResource: "logo-myarapp", withExtension: "png"),
       let logo = NSImage(contentsOf: url) {
      logo.isTemplate = true
      logo.size = NSSize(width: 18, height: 18)
      button.image = logo
    } else if let logo = NSImage(named: NSImage.Name("logo-myarapp")) {
      logo.isTemplate = true
      logo.size = NSSize(width: 18, height: 18)
      button.image = logo
    } else if #available(macOS 11.0, *) {
      button.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "MYARAP")
    } else {
      button.title = "M"
    }
    button.toolTip = "MYARAP"

    let menu = NSMenu()

    // Show — bring main window to front
    let showItem = NSMenuItem(title: "Show MYARAP", action: #selector(showMainWindow), keyEquivalent: "")
    if #available(macOS 11.0, *) {
      showItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: "Show")
    }
    menu.addItem(showItem)

    menu.addItem(.separator())

    // Setting — navigate to Flutter SettingsScreen
    let settingItem = NSMenuItem(title: "Setting", action: #selector(openSetting), keyEquivalent: ",")
    settingItem.keyEquivalentModifierMask = .command
    if #available(macOS 11.0, *) {
      settingItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Setting")
    }
    menu.addItem(settingItem)

    menu.addItem(.separator())

    menu.addItem(NSMenuItem(title: "Quit MYARAP", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

    AppDelegate.statusItem.menu = menu
  }

  @objc private func showMainWindow() {
    NSApp.setActivationPolicy(.regular)
    NSApp.windows.first?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func openSetting() {
    showMainWindow()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      MainFlutterWindow.windowChannel?.invokeMethod("openSetting", arguments: nil)
    }
  }
}

// MARK: - Mac Device Info Channel

class MacDeviceInfo {

  private static func runShell(_ command: String) -> String {
    let task = Process()
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()
    task.launchPath = "/bin/bash"
    task.arguments = ["-c", command]
    task.launch()
    task.waitUntilExit()
    return String(data: pipe.fileHandleForReading.availableData, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  private static func sysctl(_ key: String) -> String {
    return runShell("sysctl -n \(key)")
  }

  private static func systemProfilerAll(_ dataType: String) -> String {
    return runShell("system_profiler \(dataType)")
  }

  private static func extractKey(_ output: String, key: String) -> String {
    for line in output.components(separatedBy: "\n") {
      guard line.contains(key) else { continue }
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      let parts = trimmed.split(separator: ":", maxSplits: 1)
      guard parts.count >= 2 else { continue }
      let value = "\(parts[1])".trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else { continue }
      return value
    }
    return ""
  }

  private static func getSerialNumber() -> String {
    let expert = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
    guard expert > 0 else { return "" }
    defer { IOObjectRelease(expert) }
    return (IORegistryEntryCreateCFProperty(expert, kIOPlatformSerialNumberKey as CFString, kCFAllocatorDefault, 0)
      .takeUnretainedValue() as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  private static func getModelIdentifier() -> String {
    let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
    defer { IOObjectRelease(service) }
    guard let data = IORegistryEntryCreateCFProperty(service, "model" as CFString, kCFAllocatorDefault, 0)
      .takeRetainedValue() as? Data else { return "" }
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""
  }

  private static func getHardwareUUID() -> String {
    let expert = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
    guard expert > 0 else { return "" }
    defer { IOObjectRelease(expert) }
    return (IORegistryEntryCreateCFProperty(expert, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)
      .takeUnretainedValue() as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  private static func getGPU() -> String {
    return MTLCreateSystemDefaultDevice()?.name ?? ""
  }

  private static func getCPUArchitecture() -> String {
    var info = utsname()
    uname(&info)
    return withUnsafeBytes(of: &info.machine) { buf -> String in
      let data = Data(buf)
      guard let last = data.lastIndex(where: { $0 != 0 }) else { return "" }
      return String(data: data[0...last], encoding: .isoLatin1) ?? ""
    }
  }

  private static func getIPAddress() -> String {
    var result: String?
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { return "" }
    defer { freeifaddrs(ifaddr) }
    var ptr = ifaddr
    while let cur = ptr {
      defer { ptr = cur.pointee.ifa_next }
      let iface = cur.pointee
      let family = iface.ifa_addr.pointee.sa_family
      guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }
      let name = String(cString: iface.ifa_name)
      guard ["en0", "en2", "en3", "en4"].contains(name) else { continue }
      var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      getnameinfo(iface.ifa_addr, socklen_t(iface.ifa_addr.pointee.sa_len),
                  &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
      result = String(cString: host)
    }
    return result ?? ""
  }

  private static func getStorageCapacity() -> Int {
    let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeTotalCapacityKey]) ?? []
    for url in urls {
      if let total = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey]).volumeTotalCapacity {
        return total
      }
    }
    return 0
  }

  private static func getStorageAvailable() -> Int {
    let urls = FileManager.default.mountedVolumeURLs(
      includingResourceValuesForKeys: [.volumeAvailableCapacityForImportantUsageKey]) ?? []
    for url in urls {
      if let avail = try? url.resourceValues(
        forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage {
        return Int(avail)
      }
    }
    return 0
  }

  /// ทุก volume ที่ mount อยู่จริง (ไม่รวมของระบบที่ผู้ใช้ไม่เห็น เช่น /System/Volumes/*)
  ///
  /// เดิมส่งแค่ความจุ/ที่ว่างของ volume แรกที่เจอเป็นตัวเลขเดี่ยว ๆ เครื่องที่แบ่งหลาย partition
  /// หรือมีดิสก์นอกเสียบอยู่จึงเห็นแค่ลูกเดียวใน MYARAP
  /// `.skipHiddenVolumes` ตัด volume ที่ Finder ไม่โชว์ออกให้แล้ว (Preboot/Recovery/VM)
  private static func getVolumes() -> [[String: Any]] {
    let keys: [URLResourceKey] = [
      .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
      .volumeIsRemovableKey, .volumeIsInternalKey, .volumeLocalizedFormatDescriptionKey,
    ]
    let urls = FileManager.default.mountedVolumeURLs(
      includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
    var out: [[String: Any]] = []
    for url in urls {
      guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
      let total = v.volumeTotalCapacity ?? 0
      if total <= 0 { continue }
      out.append([
        "mount": url.path,
        "name": v.volumeName ?? url.lastPathComponent,
        "fs": v.volumeLocalizedFormatDescription ?? "",
        "total": total,
        "free": Int(v.volumeAvailableCapacityForImportantUsage ?? 0),
        // "/" = boot volume · removable ไว้แยกดิสก์นอกออกจากพาร์ทิชันในเครื่องฝั่ง UI
        "boot": url.path == "/",
        "removable": v.volumeIsRemovable ?? false,
      ])
    }
    return out
  }

  private static func getDisplays() -> [[String: Any]] {
    return NSScreen.screens.map { screen in
      let scale = screen.backingScaleFactor
      let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
      let isBuiltin = CGDisplayIsBuiltin(displayID) != 0
      return [
        "name": screen.localizedName,
        "resolutionX": Int(screen.frame.size.width * scale),
        "resolutionY": Int(screen.frame.size.height * scale),
        "builtin": isBuiltin,
      ]
    }
  }

  /// ดึงชื่อผู้พัฒนาจาก **code signature** ของ .app
  ///
  /// macOS ไม่มี field "Publisher" แบบ Windows registry — แหล่งที่เชื่อถือได้ที่สุดคือใบเซ็น
  /// เช่น "Developer ID Application: Google LLC (EQHXZ8M8AV)" → ตัดเหลือ "Google LLC"
  /// ของ Apple เองจะเป็น "Software Signing" / "Apple Mac OS Application Signing"
  ///
  /// ⚠️ เรียกทีละแอปบนเครื่องที่มี ~100 แอป ใช้เวลาพอควร แต่รันบน background queue
  /// และส่งแค่ตอน heartbeat (10 นาที/ครั้ง) จึงไม่กระทบ UI
  private static func publisherOf(_ url: URL) -> String {
    var codeRef: SecStaticCode?
    guard SecStaticCodeCreateWithPath(url as CFURL, [], &codeRef) == errSecSuccess,
          let code = codeRef else { return "" }
    var infoRef: CFDictionary?
    guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation),
                                        &infoRef) == errSecSuccess,
          let info = infoRef as? [String: Any] else { return "" }
    // certificates[0] = leaf → common name คือชื่อผู้เซ็น
    if let certs = info["certificates"] as? [SecCertificate], let leaf = certs.first {
      var cn: CFString?
      if SecCertificateCopyCommonName(leaf, &cn) == errSecSuccess, let name = cn as String? {
        // "Developer ID Application: Google LLC (EQHXZ8M8AV)" → "Google LLC"
        var v = name
        if let r = v.range(of: ": ") { v = String(v[r.upperBound...]) }
        if let r = v.range(of: " (") { v = String(v[..<r.lowerBound]) }
        v = v.trimmingCharacters(in: .whitespaces)
        // "Software Signing" = ใบเซ็นที่ Apple ใช้กับ component ของ macOS เอง → Apple Inc.
        if v == "Software Signing" { return "Apple Inc." }
        // ⚠️ "Apple Mac OS Application Signing" = ใบที่ Apple **เซ็นทับให้ทุกแอปที่ผ่าน App Store**
        // ไม่ใช่ชื่อผู้พัฒนา (ตรวจบนเครื่องจริง: OneDrive ของ Microsoft ก็ได้ค่านี้)
        // คืนค่าว่างดีกว่าเดาผิด — UI จะโชว์ "—"
        if v == "Apple Mac OS Application Signing" { return "" }
        return v
      }
    }
    return ""
  }

  private static func getAllApplications() -> [[String: Any]] {
    let fm = FileManager.default
    // รวมทุก location: /Applications, /System/Applications, ~/Applications
    // เก็บคู่ (dir, source) — เดิมวนอ่าน 3 ที่แล้วทิ้งข้อมูลว่ามาจากไหน ทำให้แยกไม่ออกว่า
    // อันไหนเป็นของ Apple ที่มากับเครื่อง (/System/Applications) กับที่คนลงเอง (/Applications)
    var searchDirs: [(url: URL, source: String)] = []
    for mask: FileManager.SearchPathDomainMask in [.localDomainMask, .systemDomainMask, .userDomainMask] {
      // systemDomainMask = /System/Applications = ของ Apple ล้วน ถอนไม่ได้
      let src = (mask == .systemDomainMask) ? "system" : "user"
      if let u = try? fm.url(for: .applicationDirectory, in: mask, appropriateFor: nil, create: false) {
        searchDirs.append((u, src))
        // /System/Applications/Utilities และ Subfolder อื่น
        if let subs = try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: [.isDirectoryKey],
                                                   options: [.skipsPackageDescendants, .skipsSubdirectoryDescendants]) {
          for sub in subs where sub.pathExtension != "app" {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: sub.path, isDirectory: &isDir), isDir.boolValue {
              searchDirs.append((sub, src)) // subfolder สืบทอด source ของ parent
            }
          }
        }
      }
    }
    var seen = Set<String>()
    var result: [[String: Any]] = []
    for (dir, source) in searchDirs {
      let entries = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [],
                                                  options: [.skipsPackageDescendants, .skipsSubdirectoryDescendants])) ?? []
      for url in entries where url.pathExtension == "app" {
        guard fm.isExecutableFile(atPath: url.path) else { continue }
        // Spotlight metadata (เร็ว) — แต่ถ้า app ไม่ถูก index (เช่น Microsoft Office บางเครื่อง)
        // NSMetadataItem จะเป็น nil → ต้อง fallback อ่าน Info.plist ตรงๆ ไม่งั้น app หายไปทั้งตัว
        let mdi = NSMetadataItem(url: url)
        var name = mdi?.value(forAttribute: kMDItemDisplayName as String) as? String ?? ""
        var version = mdi?.value(forAttribute: kMDItemVersion as String) as? String ?? ""
        let size = mdi?.value(forAttribute: kMDItemFSSize as String) as? Int ?? 0
        if name.isEmpty || version.isEmpty {
          if let plist = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) {
            if name.isEmpty {
              name = (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String) ?? ""
            }
            if version.isEmpty {
              version = (plist["CFBundleShortVersionString"] as? String) ?? (plist["CFBundleVersion"] as? String) ?? ""
            }
          }
        }
        if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
        guard !seen.contains(name) else { continue }
        seen.insert(name)
        // Mac App Store ฝากไฟล์ receipt ไว้ — ใช้แยก store ออกจาก user ที่ลงเอง
        let isStore = fm.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path)
        result.append([
          "name": name, "version": version, "size": size,
          "publisher": publisherOf(url),
          "source": isStore ? "store" : source,
        ])
      }
    }
    return result
  }

  static func collect(result: @escaping FlutterResult) {
    // ต้อง capture บน main thread (NSWorkspace ต้องการ main thread)
    let frontmostApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
    DispatchQueue.global(qos: .userInitiated).async {
      let osVer = ProcessInfo.processInfo.operatingSystemVersion

      let hw   = systemProfilerAll("SPHardwareDataType")
      let sw   = systemProfilerAll("SPSoftwareDataType")
      let mem  = systemProfilerAll("SPMemoryDataType")
      let stor = systemProfilerAll("SPStorageDataType")

      let info: [String: Any] = [
        "processor":       sysctl("machdep.cpu.brand_string"),
        "vendor":          sysctl("machdep.cpu.vendor"),
        "cpuFrequency":    sysctl("hw.cpufrequency"),
        "cpuFrequencyMax": sysctl("hw.cpufrequency_max"),
        "cpuFrequencyMin": sysctl("hw.cpufrequency_min"),
        "cpuArchitecture": getCPUArchitecture(),

        "modelName":       extractKey(hw, key: "Model Name"),
        "chip":            extractKey(hw, key: "Chip"),
        "totalCores":      extractKey(hw, key: "Total Number of Cores"),
        "memory":          extractKey(hw, key: "Memory"),
        "firmwareVersion": extractKey(hw, key: "System Firmware Version"),

        "modelIdentifier": getModelIdentifier(),
        "serialNumber":    getSerialNumber(),
        "hardwareUUID":    getHardwareUUID(),

        "systemVersion":   extractKey(sw, key: "System Version"),
        "kernelVersion":   extractKey(sw, key: "Kernel Version"),
        "bootVolume":      extractKey(sw, key: "Boot Volume"),
        "bootMode":        extractKey(sw, key: "Boot Mode"),
        "computerName":    extractKey(sw, key: "Computer Name"),
        "spUserName":      extractKey(sw, key: "User Name"),
        "timeSinceBoot":   extractKey(sw, key: "Time since boot"),
        "fullUserName":    NSFullUserName(),
        "hostName":        Host.current().name ?? "",
        "localizedName":   Host.current().localizedName ?? "",
        "osVersionMajor":  osVer.majorVersion,
        "osVersionMinor":  osVer.minorVersion,
        "osVersionPatch":  osVer.patchVersion,

        "memoryType":         extractKey(mem, key: "Type"),
        "memoryManufacturer": extractKey(mem, key: "Manufacturer"),

        "storageName":      extractKey(stor, key: "Device Name"),
        "storageType":      extractKey(stor, key: "Medium"),
        "storageCapacity":  getStorageCapacity(),
        "storageAvailable": getStorageAvailable(),
      "volumes":          getVolumes(),

        "displays": getDisplays(),
        "gpu":      getGPU(),
        "ipAddress": getIPAddress(),
        "applications": getAllApplications(),
        "frontmostApp": frontmostApp
      ]

      DispatchQueue.main.async { result(info) }
    }
  }
}
