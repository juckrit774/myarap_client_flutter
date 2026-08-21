import Cocoa
import FlutterMacOS
import IOKit
import Metal
import SystemConfiguration

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


  /// การ์ดเครือข่ายทั้งหมดที่ใช้งานอยู่ — IPv4 + prefix + MAC ต่อใบ
  ///
  /// 🔴 **ต้องเป็น list ต่อ interface ไม่ใช่ค่าเดียว** — `getIPAddress()` เดิมวนทับค่าไปเรื่อย ๆ
  /// แล้วคืน "ตัวสุดท้ายที่เจอ" เครื่องที่มีทั้งสาย LAN และ Wi-Fi จึงได้ค่าที่ไม่แน่นอนว่าเป็นของใบไหน
  /// (บทเรียนเดียวกับ `getVolumes()` ที่เดิมส่งไดรฟ์เดียว)
  ///
  /// ⚠️ **ไม่เรียก process ภายนอกเลย** — แอปรันใน sandbox (`com.apple.security.app-sandbox`)
  /// `route`/`ipconfig`/`scutil` จึงเรียกไม่ได้ · gateway ใช้ SystemConfiguration แทน ซึ่ง sandbox อนุญาต
  ///
  /// ⚠️ **gateway ได้เฉพาะของ interface หลัก** (SCDynamicStore เก็บ Router ระดับ global ตัวเดียว)
  /// ใบอื่นจึงคืนค่าว่าง — ฝั่ง MYARAP ไม่ได้ใช้ค่านี้เป็นหลักอยู่แล้วเพราะ gateway เป็นคุณสมบัติของ
  /// **ซับเน็ต** ไม่ใช่ของเครื่อง
  private static func getInterfaces() -> [[String: Any]] {
    // ── MAC ต่อชื่อ interface (มาจาก entry ชนิด AF_LINK คนละ entry กับ AF_INET) ──
    var macByName: [String: String] = [:]
    // ── IPv4 + netmask ต่อชื่อ interface ──
    var ipv4ByName: [String: (ip: String, prefix: Int)] = [:]

    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { return [] }
    defer { freeifaddrs(ifaddr) }

    var ptr = ifaddr
    while let cur = ptr {
      defer { ptr = cur.pointee.ifa_next }
      let iface = cur.pointee
      let name = String(cString: iface.ifa_name)
      let flags = Int32(iface.ifa_flags)
      // ข้ามใบที่ปิดอยู่และ loopback — ไม่ใช่ที่อยู่ที่ใช้สื่อสารกับใครจริง
      if flags & IFF_UP == 0 || flags & IFF_LOOPBACK != 0 { continue }
      guard let addr = iface.ifa_addr else { continue }

      switch Int32(addr.pointee.sa_family) {
      case AF_LINK:
        // sockaddr_dl — MAC อยู่หลังชื่อ interface ในบัฟเฟอร์เดียวกัน
        addr.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { dl in
          let d = dl.pointee
          guard d.sdl_alen == 6 else { return }   // เอาเฉพาะ Ethernet/Wi-Fi (6 ไบต์)
          // 🔴 **ห้ามคัดลอก `sdl_data` ออกมาเป็น tuple แล้วอ่าน** — C ประกาศไว้เป็น `char[12]`
          // แต่ของจริงเป็น variable-length ที่ยาวเกินขอบเขตนั้น (ชื่อ interface + MAC ต่อกัน)
          // Swift เห็นเป็น tuple 12 ไบต์ พอชื่อยาวจน `sdl_nlen + 6 > 12` การอ่านจะเกินขอบเขต
          // → **`Fatal error` ทำให้แอปดับทั้งตัวก่อนได้ส่ง heartbeat** (เจอจริงตอนรันบนเครื่องนี้)
          // ต้องอ่านจาก pointer ดิบพร้อม offset ซึ่งชี้ไปที่บัฟเฟอร์เต็มของจริง
          let base = UnsafeRawPointer(dl) + MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data)! + Int(d.sdl_nlen)
          let bytes = (0..<6).map { base.load(fromByteOffset: $0, as: UInt8.self) }
          macByName[name] = bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
        }
      case AF_INET:
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
        let ip = String(cString: host)
        // ข้าม link-local (169.254.x) = ที่อยู่ที่เครื่องตั้งเองเพราะหา DHCP ไม่เจอ ไม่ใช่ที่อยู่จริง
        if ip.hasPrefix("169.254.") { continue }
        var prefix = 0
        if let mask = iface.ifa_netmask {
          mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { m in
            prefix = String(UInt32(bigEndian: m.pointee.sin_addr.s_addr), radix: 2)
              .filter { $0 == "1" }.count
          }
        }
        ipv4ByName[name] = (ip, prefix)
      default:
        break
      }
    }

    // ── ชนิดของการ์ด (สาย/ไร้สาย) ──
    //
    // 🔴 **ชื่อ BSD บอกไม่ได้เลยว่าเป็นอะไร** — `en0` เป็น Wi-Fi บน MacBook แต่เป็นสายบน Mac ตั้งโต๊ะ
    // เดาจากชื่อจะสลับกันแบบเงียบ ๆ บนเครื่องครึ่งหนึ่ง · SCNetworkInterface บอกชนิดจริงและ
    // sandbox เรียกได้ (อ่าน config ของระบบ ไม่ได้ spawn process)
    var kindByName: [String: String] = [:]
    if let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
      for ni in all {
        guard let bsd = SCNetworkInterfaceGetBSDName(ni) as String?,
              let type = SCNetworkInterfaceGetInterfaceType(ni) as String? else { continue }
        switch type {
        case kSCNetworkInterfaceTypeIEEE80211 as String: kindByName[bsd] = "wifi"
        case kSCNetworkInterfaceTypeEthernet as String:  kindByName[bsd] = "lan"
        default: kindByName[bsd] = "other"
        }
      }
    }

    // gateway + interface หลัก จาก SystemConfiguration (ไม่ต้อง spawn process)
    var router = ""
    var primary = ""
    if let store = SCDynamicStoreCreate(nil, "MyARAP" as CFString, nil, nil),
       let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] {
      router = global["Router"] as? String ?? ""
      primary = global["PrimaryInterface"] as? String ?? ""
    }

    var out: [[String: Any]] = []
    for (name, v) in ipv4ByName {
      out.append([
        "name": name,
        "kind": kindByName[name] ?? "other",
        "ipv4": v.ip,
        "prefix": v.prefix,
        "mac": macByName[name] ?? "",
        "gateway": name == primary ? router : "",
        "primary": name == primary,
      ])
    }
    // interface หลักมาก่อนเสมอ — ฝั่ง server ใช้ตัวแรกเป็นตัวแทนของเครื่องเมื่อต้องเลือกอันเดียว
    out.sort { (($0["primary"] as? Bool) == true ? 0 : 1) < (($1["primary"] as? Bool) == true ? 0 : 1) }
    return out
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

  // สถาปัตยกรรมของแอป — `Bundle.executableArchitectures` เป็น public API และอ่านได้ใน
  // sandbox (ไม่ต้องแกะ Mach-O header เอง) · แอปที่เป็น universal จะคืนมาทั้งสองค่า
  private static func architectureOf(_ url: URL) -> String {
    guard let raw = Bundle(url: url)?.executableArchitectures else { return "" }
    let archs = raw.map { $0.intValue }
    var names: [String] = []
    // ⚠️ ใช้ค่าดิบแทน `NSBundleExecutableArchitectureARM64` เพราะสัญลักษณ์นั้นมีตั้งแต่
    // macOS 11 แต่ deployment target ของโปรเจกต์นี้คือ 10.15 → คอมไพล์ไม่ผ่าน
    // ค่า = CPU_TYPE_ARM64 (0x0100000C) ซึ่งคงที่ ไม่เปลี่ยนตามเวอร์ชัน OS
    let archARM64 = 0x0100000C
    if archs.contains(archARM64)                            { names.append("arm64") }
    if archs.contains(NSBundleExecutableArchitectureX86_64) { names.append("x86_64") }
    if archs.contains(NSBundleExecutableArchitectureI386)   { names.append("i386") }
    if names.count > 1 { return "universal" }
    return names.first ?? ""
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
        // IMPL-15 Phase 3 — bundle id + path + architecture
        // ⚠️ **ไม่มี installDate ให้ส่ง** และจงใจไม่ใช้ creation/modification date ของโฟลเดอร์
        // แทน เพราะมันถูกเขียนใหม่ทุกครั้งที่แอปอัปเดต → จะกลายเป็น "วันที่อัปเดตล่าสุด"
        // ซึ่งเป็นคนละความหมายกับที่สเปกขอ (ดู REQ-09 §4 field #7)
        let bundleID = (NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String) ?? ""
        result.append([
          "name": name, "version": version, "size": size,
          "publisher": publisherOf(url),
          "source": isStore ? "store" : source,
          "installDate": "",
          "installLocation": url.path,
          "architecture": architectureOf(url),
          "packageId": bundleID,
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
      "interfaces": getInterfaces(),
        "applications": getAllApplications(),
        "frontmostApp": frontmostApp
      ]

      DispatchQueue.main.async { result(info) }
    }
  }
}
