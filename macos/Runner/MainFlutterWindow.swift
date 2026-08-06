import Cocoa
import FlutterMacOS
import DiskArbitration
import ScreenCaptureKit
import CoreMedia
import CoreImage
import Darwin      // host_statistics/host_statistics64 (CPU/Memory), getifaddrs (Network), proc_listpids/proc_pidinfo (libproc — Process/Thread count) — sandbox-safe read-only APIs
import IOKit       // IOServiceMatching/IORegistryEntryCreateCFProperty (Disk IO stats)
import IOKit.ps    // IOPSCopyPowerSourcesInfo (Energy/Battery) — public API, sandbox-safe, ไม่ต้อง entitlement เพิ่ม
import ApplicationServices // AXIsProcessTrustedWithOptions + CGEventPost (Remote Control POC)
import CoreLocation // POC: WiFi-based location (ไม่ใช่ GPS จริง — laptop ไม่มี GPS chip) ต้อง entitlement personal-information.location + Info.plist usage description

// unified logging redact string-interpolated NSLog content เป็น <private> โดย default
// (ต้อง %{public}@ ชัดเจนถึงจะเห็นค่าจริงใน `log stream`/Console.app) — ใช้ debug ตอนพัฒนา
// เพิ่มเขียนไฟล์ debug ตรงๆ ด้วย เพราะ `log stream` ไม่เห็น NSLog ของแอปนี้เลยแม้จะใช้ %{public}@
// แล้ว (ยังไม่ทราบสาเหตุแน่ชัด) — ไฟล์อยู่ใน sandbox container ของแอปเอง อ่านจาก shell ภายนอกได้
func dlog(_ s: String) {
  NSLog("%{public}@", s)
  if let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
    let logFile = dir.appendingPathComponent("myarap-usb-debug.log")
    let line = "\(Date()) \(s)\n"
    if let data = line.data(using: .utf8) {
      if FileManager.default.fileExists(atPath: logFile.path) {
        if let handle = try? FileHandle(forWritingTo: logFile) {
          handle.seekToEndOfFile()
          handle.write(data)
          handle.closeFile()
        }
      } else {
        try? data.write(to: logFile)
      }
    }
  }
}

// ScreenCapture: capture หน้าจอหลัก → JPEG data URL (สำหรับ Remote Desktop view-only)
// ใช้ CGDisplayCreateImage (ต้องขอ Screen Recording permission ครั้งแรก — TCC prompt)
// deprecated ใน macOS 15 แต่ยังทำงาน; ScreenCaptureKit เป็น async ซับซ้อนกว่ามาก ยังไม่ใช้ใน POC นี้
// SystemMetrics: เก็บค่า Activity Monitor (CPU/Memory/Energy/Disk/Network) แบบ native ล้วน —
// แอปนี้ app-sandbox=true (ดู entitlements) → Process/NSTask shell out ไป top/vm_stat/netstat
// ใช้ไม่ได้ (บทเรียนเดิมจาก USB Control) ต้องใช้ Mach/IOKit/POSIX API ที่อ่านอย่างเดียวเท่านั้น
enum SystemMetrics {
  // เรียกบน background queue เสมอ — มี blocking sleep สั้นๆ สำหรับ delta sampling (CPU/Network/Disk)
  static func collect(completion: @escaping ([String: Any]) -> Void) {
    DispatchQueue.global(qos: .utility).async {
      let cpu = cpuUsage()
      let mem = memoryUsage()
      let disk = diskUsage()
      let diskIO = diskIOThroughput()
      let net = networkThroughput()
      let energy = energyInfo()
      let proc = processStats()
      let out: [String: Any] = [
        "cpuSystemPct": cpu.system, "cpuUserPct": cpu.user, "cpuIdlePct": cpu.idle,
        "cpuThreads": proc.threads, "cpuProcesses": proc.processes,
        "memPhysicalGB": mem.physicalGB, "memUsedGB": mem.usedGB,
        "memCachedGB": mem.cachedGB, "memSwapUsedGB": mem.swapUsedGB,
        "memAppGB": mem.appGB, "memWiredGB": mem.wiredGB, "memCompressedGB": mem.compressedGB,
        "diskFreeGB": disk.freeGB, "diskUsedGB": disk.usedGB, "diskTotalGB": disk.totalGB,
        // ต่อพาร์ทิชัน — 3 field ข้างบนยังเป็นของ "/" เหมือนเดิม กันของเก่าพัง
        "volumes": SystemMetrics.volumeUsages(),
        "diskReadsCount": diskIO.readsCount, "diskWritesCount": diskIO.writesCount,
        "diskReadsPerSec": diskIO.readsPerSec, "diskWritesPerSec": diskIO.writesPerSec,
        "diskDataReadGB": diskIO.dataReadGB, "diskDataWrittenGB": diskIO.dataWrittenGB,
        "diskReadKBs": diskIO.readKBs, "diskWriteKBs": diskIO.writeKBs,
        "netRxKBs": net.rxKBs, "netTxKBs": net.txKBs,
        "netPacketsIn": net.packetsIn, "netPacketsOut": net.packetsOut,
        "netPacketsInPerSec": net.packetsInPerSec, "netPacketsOutPerSec": net.packetsOutPerSec,
        "netDataReceivedGB": net.dataReceivedGB, "netDataSentGB": net.dataSentGB,
        "hasBattery": energy.hasBattery, "batteryPct": energy.batteryPct,
        "batteryCharged": energy.charged, "timeOnACMinutes": energy.timeOnACMinutes,
        // Energy Impact ไม่มี public API ให้ real wattage (ต้อง IOReport/root) — ใช้ non-idle CPU
        // % เป็น proxy สำหรับกราฟเท่านั้น (documented approximation, ดู memory: activity-monitor-status)
        "energyImpactPct": cpu.system + cpu.user,
      ]
      DispatchQueue.main.async { completion(out) }
    }
  }

  // ---- CPU: System/User/Idle % ผ่าน host_statistics(HOST_CPU_LOAD_INFO), delta sampling 300ms ----
  private static func cpuTicks() -> (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)? {
    var cpuLoad = host_cpu_load_info()
    var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &cpuLoad) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }
    let t = cpuLoad.cpu_ticks
    // CPU_STATE_USER=0, CPU_STATE_SYSTEM=1, CPU_STATE_IDLE=2, CPU_STATE_NICE=3 (<mach/machine.h>)
    return (t.0, t.1, t.2, t.3)
  }

  private static func cpuUsage() -> (system: Double, user: Double, idle: Double) {
    guard let t0 = cpuTicks() else { return (0, 0, 0) }
    Thread.sleep(forTimeInterval: 0.3)
    guard let t1 = cpuTicks() else { return (0, 0, 0) }
    let dUser = Double(t1.user &- t0.user)
    let dSystem = Double(t1.system &- t0.system)
    let dIdle = Double(t1.idle &- t0.idle)
    let dNice = Double(t1.nice &- t0.nice)
    let total = dUser + dSystem + dIdle + dNice
    guard total > 0 else { return (0, 0, 100) }
    return (dSystem / total * 100, (dUser + dNice) / total * 100, dIdle / total * 100)
  }

  // ---- Memory: host_statistics64(HOST_VM_INFO64) — สูตรเดียวกับที่ Activity Monitor ใช้ ----
  // App/Wired/Compressed ต้องรวมกันได้ = usedGB เสมอ (by construction — App=active, ไม่ใช่สูตร
  // private ที่แท้จริงของ Apple ซึ่งไม่เปิดเผย แต่เป็น approximation ที่ tool โอเพนซอร์สหลายตัวใช้)
  private static func memoryUsage() -> (physicalGB: Double, usedGB: Double, cachedGB: Double,
                                         swapUsedGB: Double, appGB: Double, wiredGB: Double, compressedGB: Double) {
    var pageSize: vm_size_t = 0
    host_page_size(mach_host_self(), &pageSize)
    var vmStat = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &vmStat) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
      }
    }
    let gb = Double(pageSize) / 1_073_741_824.0
    guard result == KERN_SUCCESS else { return (0, 0, 0, 0, 0, 0, 0) }
    let physicalGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
    let appGB = Double(vmStat.active_count) * gb
    let wiredGB = Double(vmStat.wire_count) * gb
    let compressedGB = Double(vmStat.compressor_page_count) * gb
    // Used = App Memory + Wired + Compressed (สูตร "Memory Used" ของ Activity Monitor)
    let usedGB = appGB + wiredGB + compressedGB
    let cachedGB = Double(vmStat.external_page_count) * gb // "Cached Files" (file-backed pages)
    var swapUsage = xsw_usage()
    var size = MemoryLayout<xsw_usage>.size
    sysctlbyname("vm.swapusage", &swapUsage, &size, nil, 0)
    let swapUsedGB = Double(swapUsage.xsu_used) / 1_073_741_824.0
    return (physicalGB, usedGB, cachedGB, swapUsedGB, appGB, wiredGB, compressedGB)
  }

  // ---- Disk: volume capacity ของ "/" (ไม่ใช่ IOKit read/write IOPS — ตัดสินใจ simplify) ----
  /// ความจุของทุก volume ที่ mount อยู่ — ไม่ใช่แค่ "/" ตัวเดียว
  /// เครื่องที่แบ่งหลายพาร์ทิชันหรือมีดิสก์นอกเสียบ จะเห็นครบทุกลูกในการ์ด Disk
  /// `.skipHiddenVolumes` ตัด Preboot/Recovery/VM ที่ผู้ใช้ไม่เห็นใน Finder ออกให้แล้ว
  static func volumeUsages() -> [[String: Any]] {
    let keys: [URLResourceKey] = [
      .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
      .volumeIsRemovableKey,
    ]
    let urls = FileManager.default.mountedVolumeURLs(
      includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
    let gb = 1_073_741_824.0
    var out: [[String: Any]] = []
    for url in urls {
      guard let v = try? url.resourceValues(forKeys: Set(keys)),
            let total = v.volumeTotalCapacity, total > 0 else { continue }
      let totalGB = Double(total) / gb
      let freeGB = Double(v.volumeAvailableCapacityForImportantUsage ?? 0) / gb
      out.append([
        "mount": url.path,
        "name": v.volumeName ?? url.lastPathComponent,
        "totalGB": totalGB,
        "freeGB": freeGB,
        "usedGB": max(0, totalGB - freeGB),
        "boot": url.path == "/",
        "removable": v.volumeIsRemovable ?? false,
      ])
    }
    return out
  }

  private static func diskUsage() -> (freeGB: Double, usedGB: Double, totalGB: Double) {
    guard let values = try? URL(fileURLWithPath: "/").resourceValues(
      forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
      let total = values.volumeTotalCapacity else { return (0, 0, 0) }
    let avail = values.volumeAvailableCapacityForImportantUsage ?? 0
    let totalGB = Double(total) / 1_073_741_824.0
    let freeGB = Double(avail) / 1_073_741_824.0
    return (freeGB, max(0, totalGB - freeGB), totalGB)
  }

  // ---- Network: getifaddrs delta sampling 500ms (รวมทุก interface en*, ข้าม loopback) ----
  // คืนทั้ง cumulative counter (ตั้งแต่ boot — ใช้แสดง "Data received/sent"/"Packets in/out" ตรงๆ)
  // และ rate (คำนวณจาก delta ของ sampling window — ใช้แสดง "…/sec")
  private static func networkCounters() -> (rxBytes: UInt64, txBytes: UInt64, rxPackets: UInt64, txPackets: UInt64) {
    var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return (0, 0, 0, 0) }
    defer { freeifaddrs(ifaddrPtr) }
    var rxB: UInt64 = 0, txB: UInt64 = 0, rxP: UInt64 = 0, txP: UInt64 = 0
    var ptr: UnsafeMutablePointer<ifaddrs>? = first
    while let p = ptr {
      let ifa = p.pointee
      let name = String(cString: ifa.ifa_name)
      if name.hasPrefix("en"), let data = ifa.ifa_data {
        let netData = data.assumingMemoryBound(to: if_data.self).pointee
        rxB += UInt64(netData.ifi_ibytes); txB += UInt64(netData.ifi_obytes)
        rxP += UInt64(netData.ifi_ipackets); txP += UInt64(netData.ifi_opackets)
      }
      ptr = ifa.ifa_next
    }
    return (rxB, txB, rxP, txP)
  }

  private static func networkThroughput() -> (rxKBs: Double, txKBs: Double, packetsIn: UInt64, packetsOut: UInt64,
                                                packetsInPerSec: Double, packetsOutPerSec: Double,
                                                dataReceivedGB: Double, dataSentGB: Double) {
    let t0 = networkCounters()
    Thread.sleep(forTimeInterval: 0.5)
    let t1 = networkCounters()
    let rxKBs = max(0, Double(t1.rxBytes &- t0.rxBytes) / 1024.0 / 0.5)
    let txKBs = max(0, Double(t1.txBytes &- t0.txBytes) / 1024.0 / 0.5)
    let pInSec = max(0, Double(t1.rxPackets &- t0.rxPackets) / 0.5)
    let pOutSec = max(0, Double(t1.txPackets &- t0.txPackets) / 0.5)
    return (rxKBs, txKBs, t1.rxPackets, t1.txPackets, pInSec, pOutSec,
            Double(t1.rxBytes) / 1_073_741_824.0, Double(t1.txBytes) / 1_073_741_824.0)
  }

  // ---- Disk IO: IOKit IOBlockStorageDriver "Statistics" property (public, sandbox-safe read) ----
  // คืนทั้ง cumulative operations/bytes (ตั้งแต่ boot) และ rate ที่คำนวณจาก delta 500ms
  private static func diskIOCounters() -> (reads: UInt64, writes: UInt64, readBytes: UInt64, writeBytes: UInt64) {
    var totalReads: UInt64 = 0, totalWrites: UInt64 = 0, totalReadBytes: UInt64 = 0, totalWriteBytes: UInt64 = 0
    var iter: io_iterator_t = 0
    let matching = IOServiceMatching("IOBlockStorageDriver")
    // kIOMasterPortDefault (deprecated name, ไม่ใช่ kIOMainPortDefault) — deployment target ของ
    // แอปนี้คือ macOS 10.15 ซึ่ง kIOMainPortDefault (12.0+) ยังไม่มี, ตัวเก่ายังทำงานได้ปกติ
    guard IOServiceGetMatchingServices(kIOMasterPortDefault, matching, &iter) == KERN_SUCCESS else { return (0, 0, 0, 0) }
    defer { IOObjectRelease(iter) }
    var service = IOIteratorNext(iter)
    while service != 0 {
      defer { IOObjectRelease(service); service = IOIteratorNext(iter) }
      guard let cfProp = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0) else { continue }
      guard let dict = cfProp.takeRetainedValue() as? [String: Any] else { continue }
      if let v = dict["Operations (Read)"] as? UInt64 { totalReads += v }
      if let v = dict["Operations (Write)"] as? UInt64 { totalWrites += v }
      if let v = dict["Bytes (Read)"] as? UInt64 { totalReadBytes += v }
      if let v = dict["Bytes (Write)"] as? UInt64 { totalWriteBytes += v }
    }
    return (totalReads, totalWrites, totalReadBytes, totalWriteBytes)
  }

  private static func diskIOThroughput() -> (readsCount: UInt64, writesCount: UInt64, readsPerSec: Double,
                                              writesPerSec: Double, dataReadGB: Double, dataWrittenGB: Double,
                                              readKBs: Double, writeKBs: Double) {
    let t0 = diskIOCounters()
    Thread.sleep(forTimeInterval: 0.5)
    let t1 = diskIOCounters()
    let readsPerSec = max(0, Double(t1.reads &- t0.reads) / 0.5)
    let writesPerSec = max(0, Double(t1.writes &- t0.writes) / 0.5)
    let readKBs = max(0, Double(t1.readBytes &- t0.readBytes) / 1024.0 / 0.5)
    let writeKBs = max(0, Double(t1.writeBytes &- t0.writeBytes) / 1024.0 / 0.5)
    return (t1.reads, t1.writes, readsPerSec, writesPerSec,
            Double(t1.readBytes) / 1_073_741_824.0, Double(t1.writeBytes) / 1_073_741_824.0, readKBs, writeKBs)
  }

  // ---- Process/Thread count — proc_listpids (libproc, sandbox-safe: enumerating PIDs ไม่ต้อง
  // เป็นเจ้าของ process) แต่ proc_pidinfo(PROC_PIDTASKINFO) ของ process อื่นที่ไม่ใช่ของเราเอง
  // จะ fail (ต้องเป็นเจ้าของ/root) → thread count นี่ "undercounted" เทียบกับ Activity Monitor
  // จริงที่รันด้วยสิทธิ์สูงกว่า — documented limitation ไม่ใช่บั๊ก (ดู memory: activity-monitor-status)
  private static func processStats() -> (processes: Int, threads: Int) {
    let bufSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
    guard bufSize > 0 else { return (0, 0) }
    let count = Int(bufSize) / MemoryLayout<pid_t>.size
    var pids = [pid_t](repeating: 0, count: count)
    let actualSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bufSize)
    guard actualSize > 0 else { return (0, 0) }
    let actualCount = Int(actualSize) / MemoryLayout<pid_t>.size
    var threadTotal = 0
    for i in 0..<actualCount where pids[i] != 0 {
      var info = proc_taskinfo()
      let size = Int32(MemoryLayout<proc_taskinfo>.size)
      if proc_pidinfo(pids[i], PROC_PIDTASKINFO, 0, &info, size) == size {
        threadTotal += Int(info.pti_threadnum)
      }
    }
    return (actualCount, threadTotal)
  }

  // ---- Energy (battery) — IOPSCopyPowerSourcesInfo (public IOKit API, sandbox-safe) ----
  // "Time on AC" ไม่มี system API ให้ตรงๆ — track เอง in-process (reset ทุกครั้ง agent restart,
  // ยอมรับเป็น approximation สำหรับ POC — ไม่ persist ข้าม launch)
  private static var acConnectedSince: Date?

  private static func energyInfo() -> (hasBattery: Bool, batteryPct: Double, charged: Bool, timeOnACMinutes: Double) {
    let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let sources = IOPSCopyPowerSourcesList(blob).takeRetainedValue() as [CFTypeRef]
    guard let first = sources.first,
          let desc = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any] else {
      // ไม่มีแบตเลย (desktop Mac) = ใช้ไฟบ้านตลอด ไม่มี power source ให้เช็คสถานะ AC/battery
      if acConnectedSince == nil { acConnectedSince = Date() }
      let mins = Date().timeIntervalSince(acConnectedSince!) / 60
      return (false, 0, false, mins)
    }
    let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
    let maxCap = desc[kIOPSMaxCapacityKey] as? Int ?? 100
    let pct = maxCap > 0 ? Double(current) / Double(maxCap) * 100 : 0
    let charged = desc[kIOPSIsChargedKey] as? Bool ?? false
    let state = desc[kIOPSPowerSourceStateKey] as? String ?? ""
    let onAC = state == kIOPSACPowerValue
    if onAC {
      if acConnectedSince == nil { acConnectedSince = Date() }
    } else {
      acConnectedSince = nil
    }
    let mins = acConnectedSince.map { Date().timeIntervalSince($0) / 60 } ?? 0
    return (true, pct, charged, mins)
  }
}

enum ScreenCapture {
  static func capture(maxWidth: Int, quality: Double, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      let displayID = CGMainDisplayID()
      guard let cgImage = CGDisplayCreateImage(displayID) else {
        // nil = ยังไม่ได้อนุญาต Screen Recording (หรือจอ locked) — คืน error ให้ Flutter รู้
        DispatchQueue.main.async {
          result(FlutterError(code: "no_permission",
                              message: "Screen capture failed — ต้องอนุญาต Screen Recording ใน System Settings",
                              details: nil))
        }
        return
      }
      // ย่อขนาดถ้ากว้างเกิน maxWidth (ลด bandwidth/CPU — remote view ไม่ต้อง full res)
      var img = NSImage(cgImage: cgImage, size: .zero)
      let w = CGFloat(cgImage.width), h = CGFloat(cgImage.height)
      if Int(w) > maxWidth {
        let scale = CGFloat(maxWidth) / w
        let newSize = NSSize(width: maxWidth, height: Int(h * scale))
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        img.draw(in: NSRect(origin: .zero, size: newSize),
                 from: NSRect(x: 0, y: 0, width: w, height: h),
                 operation: .copy, fraction: 1.0)
        resized.unlockFocus()
        img = resized
      }
      guard let tiff = img.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
        DispatchQueue.main.async {
          result(FlutterError(code: "encode_failed", message: "JPEG encode failed", details: nil))
        }
        return
      }
      let dataUrl = "data:image/jpeg;base64," + jpeg.base64EncodedString()
      DispatchQueue.main.async { result(dataUrl) }
    }
  }
}

// LocationProvider: WiFi-based location ผ่าน CoreLocation (POC — เครื่อง desktop/laptop ไม่มี GPS chip
// จริง, ใช้ WiFi-AP database ของ Apple แทน — ความแม่นยำระดับอาคาร/ย่าน ไม่ใช่ระดับห้อง)
// ต้องขอ authorization ครั้งแรก (macOS โชว์ system prompt) — ถ้า user ปฏิเสธ/ยังไม่ตัดสินใจ คืน nil เงียบๆ
// ไม่บล็อก metrics round อื่น (เหมือน pattern อื่นๆ ใน SystemMetrics — best-effort)
final class LocationProvider: NSObject, CLLocationManagerDelegate {
  static let shared = LocationProvider()
  private let manager = CLLocationManager()
  private var pending: ((CLLocationCoordinate2D?) -> Void)?

  override init() {
    super.init()
    manager.delegate = self
  }

  // ใช้ class method CLLocationManager.authorizationStatus() (deprecated แต่รองรับ macOS 10.15+)
  // แทน instance property .authorizationStatus (ต้อง macOS 11+) — deployment target โปรเจกต์นี้คือ 10.15
  func requestLocation(completion: @escaping (CLLocationCoordinate2D?) -> Void) {
    guard CLLocationManager.locationServicesEnabled() else { completion(nil); return }
    pending = completion
    switch CLLocationManager.authorizationStatus() {
    case .notDetermined:
      manager.requestAlwaysAuthorization() // เจอ system prompt ครั้งแรก — ผลจะมาที่ locationManager(didChangeAuthorization:)
    case .authorizedAlways:
      manager.requestLocation()
    default: // .denied / .restricted
      pending?(nil)
      pending = nil
    }
  }

  // delegate แบบเก่า (macOS 10.15-compatible) — รับ status เป็น parameter ตรงๆ แทนอ่านจาก property
  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    guard pending != nil else { return }
    if status == .authorizedAlways {
      manager.requestLocation()
    } else if status == .denied || status == .restricted {
      pending?(nil)
      pending = nil
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    pending?(locations.first?.coordinate)
    pending = nil
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    pending?(nil)
    pending = nil
  }
}

// RemoteCapture: capture ต่อเนื่องด้วย ScreenCaptureKit (SCStream) — macOS 12.3+
// เหตุผลที่ใช้แทน CGDisplayCreateImage: macOS ผูก "screen recording indicator" (ไอคอนม่วง
// Control Center) เข้ากับ lifecycle ของ SCStream โดยตรง → หยุด stream = indicator หายทันที
// (CGDisplayCreateImage แบบ one-shot ทำให้ indicator ค้าง ~1 นาทีหลัง capture ครั้งสุดท้าย
// และไม่มี API สั่งปิดตรงๆ). frame ล่าสุดเก็บใน memory, Flutter poll ผ่าน latestFrameDataURL()
@available(macOS 12.3, *)
final class RemoteCapture: NSObject, SCStreamOutput {
  static let shared = RemoteCapture()
  private var stream: SCStream?
  private let ciContext = CIContext()
  private let lock = NSLock()
  private var latestJPEG: Data?
  private var maxWidth: Int = 1920
  private var quality: Double = 1.0
  private(set) var running = false

  func start(maxWidth: Int, quality: Double) {
    if running { return }
    self.maxWidth = maxWidth
    self.quality = quality
    running = true
    SCShareableContent.getWithCompletionHandler { [weak self] content, err in
      guard let self = self, self.running else { return }
      if err != nil {
        // SCK ใช้ไม่ได้ (เช่น ad-hoc build ไม่ได้ grant) → running=false → captureScreen fallback CGDisplayCreateImage
        self.running = false
        return
      }
      guard let display = content?.displays.first else {
        self.running = false
        return
      }
      let filter = SCContentFilter(display: display, excludingWindows: [])
      let config = SCStreamConfiguration()
      config.width = display.width * 2   // pixel dimensions (Retina) — output buffer size
      config.height = display.height * 2
      config.minimumFrameInterval = CMTime(value: 1, timescale: 3) // ~3 fps
      config.queueDepth = 5
      config.pixelFormat = kCVPixelFormatType_32BGRA
      let s = SCStream(filter: filter, configuration: config, delegate: nil)
      do {
        try s.addStreamOutput(self, type: .screen,
                              sampleHandlerQueue: DispatchQueue(label: "com.myarap.remote.capture"))
        s.startCapture { _ in }
        self.stream = s
      } catch {
        self.running = false
      }
    }
  }

  func stop() {
    running = false
    stream?.stopCapture { _ in }
    stream = nil
    lock.lock(); latestJPEG = nil; lock.unlock()
  }

  func latestFrameDataURL() -> String? {
    lock.lock(); let d = latestJPEG; lock.unlock()
    guard let d = d else { return nil }
    return "data:image/jpeg;base64," + d.base64EncodedString()
  }

  func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
              of type: SCStreamOutputType) {
    guard type == .screen, CMSampleBufferIsValid(sampleBuffer) else { return }
    // ตรวจ frame status — SCStream ส่ง .idle/.blank ตอนจอไม่เปลี่ยน (ไม่มี image buffer ใช้ได้)
    if let attachs = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
       let statusRaw = attachs.first?[.status] as? Int,
       let status = SCFrameStatus(rawValue: statusRaw), status != .complete {
      return // idle/blank/suspended — ข้าม (คงเฟรมล่าสุดไว้)
    }
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    var ci = CIImage(cvPixelBuffer: pixelBuffer)
    let w = CVPixelBufferGetWidth(pixelBuffer), h = CVPixelBufferGetHeight(pixelBuffer)
    var tw = w, th = h
    if w > maxWidth {
      let scale = Double(maxWidth) / Double(w)
      tw = maxWidth; th = Int(Double(h) * scale)
      ci = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
    guard let cg = ciContext.createCGImage(ci, from: CGRect(x: 0, y: 0, width: tw, height: th)) else { return }
    let bitmap = NSBitmapImageRep(cgImage: cg)
    guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]) else { return }
    lock.lock(); latestJPEG = jpeg; lock.unlock()
  }
}

// RemoteEventStreamHandler: ส่ง event Swift → Flutter (เช่น ผู้ใช้กด Disconnect บน indicator)
class RemoteEventStreamHandler: NSObject, FlutterStreamHandler {
  static var eventSink: FlutterEventSink?
  static func emit(_ payload: [String: Any]) {
    DispatchQueue.main.async { eventSink?(payload) }
  }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    RemoteEventStreamHandler.eventSink = events
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    RemoteEventStreamHandler.eventSink = nil
    return nil
  }
}

// target ของปุ่ม "หยุด" บน indicator (NSButton.target เป็น weak ต้อง retain แยก)
class RemoteDisconnectTarget: NSObject {
  @objc func tapped() {
    RemoteEventStreamHandler.emit(["event": "disconnect"])
  }
}

// RemoteConsent: แสดง NSAlert ขอความยินยอมก่อนให้ดูหน้าจอ (view-only) + indicator ระหว่างถูกดู
// ─────────────────────────────────────────────────────────────────────────────
// RemoteInput — ยิงเมาส์/คีย์บอร์ดเข้าระบบจริงด้วย CGEventPost (Remote Control POC)
//
// ⚠️⚠️ ต้องได้สิทธิ์ **Accessibility** (System Settings › Privacy & Security › Accessibility)
// คนละตัวกับ Screen Recording ที่ขอไว้แล้วสำหรับ capture หน้าจอ · **สั่งเปิดด้วยโค้ดไม่ได้**
// ทำได้แค่เด้ง prompt พาไปหน้านั้น ผู้ใช้ต้องกดสวิตช์เอง
//
// ⚠️ TCC ผูกกับ **ลายเซ็น** — ถ้า build ไม่เซ็นแบบคงที่ สิทธิ์จะหลุดทุก rebuild
//    ต้อง build ด้วย build_signed_macos.sh เท่านั้น (บทเรียนเดิมจาก Screen Recording)
//
// ⚠️ แอปนี้เปิด App Sandbox อยู่ — ยังไม่ยืนยันว่า CGEventPost ทะลุ sandbox ได้จริงหรือไม่
//    ถ้ายิงแล้วไม่มีผล ทั้งที่ AXIsProcessTrusted = true → แปลว่า sandbox บล็อก
//    ต้องตัดสินใจว่าจะปิด sandbox ไหม (กระทบ USB Block ที่พึ่ง DiskArbitration ใน sandbox)
/// ลายเซ็นที่ประทับลง event ทุกตัวที่ **เรายิงเข้าระบบเอง** (`eventSourceUserData`)
///
/// จำเป็นเพราะ "กด Esc ค้างเพื่อหยุด" บนแถบแจ้งเตือนดักคีย์ทั้งเครื่อง — ถ้าไม่แยก
/// แอดมินที่กด Esc ค้างในโปรแกรมฝั่งเครื่องนี้ (เช่นออกจาก vim) จะตัด session ตัวเองทิ้ง
/// โดยที่เจ้าของเครื่องไม่ได้แตะอะไรเลย
let kMyarapInjectedTag: Int64 = 0x4D594152 // "MYAR"

enum RemoteInput {
  /// พิกัดที่ viewer ส่งมาเป็นสัดส่วน 0..1 ของจอ ไม่ใช่ px
  /// เพราะ <video> ฝั่ง viewer ถูกย่อ/ขยายตามขนาด drawer — ส่ง px มาจะเพี้ยนทันทีที่ resize
  private static func point(_ nx: Double, _ ny: Double) -> CGPoint {
    let d = CGMainDisplayID()
    let w = Double(CGDisplayPixelsWide(d))
    let h = Double(CGDisplayPixelsHigh(d))
    // clamp กัน viewer ส่งค่านอกช่วงแล้ว cursor กระเด็นออกนอกจอ
    let x = min(max(nx, 0), 1) * w
    let y = min(max(ny, 0), 1) * h
    return CGPoint(x: x, y: y)
  }

  /// มีสิทธิ์ Accessibility แล้วหรือยัง · prompt=true → เด้ง dialog พาไป System Settings
  static func trusted(prompt: Bool) -> Bool {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
  }

  private static var lastPos = CGPoint(x: 0, y: 0)
  // ปุ่มที่กดค้างอยู่ — ต้องจำเพราะ CGEvent ของการ "ลาก" (drag) เป็น event คนละชนิดกับ move
  private static var downButton: CGMouseButton? = nil

  private static func post(_ type: CGEventType, _ pos: CGPoint, _ btn: CGMouseButton) {
    guard let ev = CGEvent(mouseEventSource: nil, mouseType: type,
                           mouseCursorPosition: pos, mouseButton: btn) else { return }
    ev.setIntegerValueField(.eventSourceUserData, value: kMyarapInjectedTag)
    ev.post(tap: .cghidEventTap)
  }

  static func mouseMove(_ nx: Double, _ ny: Double) {
    let p = point(nx, ny)
    lastPos = p
    // กดค้างอยู่ = ต้องส่ง drag ไม่ใช่ move ไม่งั้นการลากจะไม่ทำงาน
    if let b = downButton {
      post(b == .right ? .rightMouseDragged : .leftMouseDragged, p, b)
    } else {
      post(.mouseMoved, p, .left)
    }
  }

  static func mouseDown(_ button: Int) {
    let b: CGMouseButton = (button == 1) ? .right : (button == 2 ? .center : .left)
    downButton = b
    post(b == .right ? .rightMouseDown : (b == .center ? .otherMouseDown : .leftMouseDown), lastPos, b)
  }

  static func mouseUp(_ button: Int) {
    let b: CGMouseButton = (button == 1) ? .right : (button == 2 ? .center : .left)
    downButton = nil
    post(b == .right ? .rightMouseUp : (b == .center ? .otherMouseUp : .leftMouseUp), lastPos, b)
  }

  static func scroll(_ dy: Int, _ dx: Int) {
    // wheelCount:2 = รองรับทั้งแนวตั้งและแนวนอน · หน่วยเป็น "line" ไม่ใช่ pixel
    // หาร 40 เพราะ deltaY ของเบราว์เซอร์มักเป็น ~100/คลิก แต่ line ของ macOS ละเอียดกว่ามาก
    guard let ev = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                           wheel1: Int32(-dy / 40), wheel2: Int32(-dx / 40), wheel3: 0) else { return }
    ev.setIntegerValueField(.eventSourceUserData, value: kMyarapInjectedTag)
    ev.post(tap: .cghidEventTap)
  }

  // ── คีย์บอร์ด ──────────────────────────────────────────────────────────────
  //
  // viewer ส่ง `KeyboardEvent.code` มา (ตำแหน่งปุ่มจริง) **ไม่ใช่** `key`
  // เพราะ `key` เปลี่ยนตามภาษา/layout — พิมพ์ไทยแล้วกด Q จะได้ "ๆ" ทำให้ map ไม่ได้
  // ส่วน `code` คงที่เสมอ ตรงกับ virtual keycode ของ macOS แบบ 1:1
  private static let keyMap: [String: CGKeyCode] = [
    "KeyA": 0, "KeyS": 1, "KeyD": 2, "KeyF": 3, "KeyH": 4, "KeyG": 5, "KeyZ": 6, "KeyX": 7,
    "KeyC": 8, "KeyV": 9, "KeyB": 11, "KeyQ": 12, "KeyW": 13, "KeyE": 14, "KeyR": 15,
    "KeyY": 16, "KeyT": 17, "Digit1": 18, "Digit2": 19, "Digit3": 20, "Digit4": 21,
    "Digit6": 22, "Digit5": 23, "Equal": 24, "Digit9": 25, "Digit7": 26, "Minus": 27,
    "Digit8": 28, "Digit0": 29, "BracketRight": 30, "KeyO": 31, "KeyU": 32,
    "BracketLeft": 33, "KeyI": 34, "KeyP": 35, "Enter": 36, "KeyL": 37, "KeyJ": 38,
    "Quote": 39, "KeyK": 40, "Semicolon": 41, "Backslash": 42, "Comma": 43, "Slash": 44,
    "KeyN": 45, "KeyM": 46, "Period": 47, "Tab": 48, "Space": 49, "Backquote": 50,
    "Backspace": 51, "Escape": 53,
    "ArrowLeft": 123, "ArrowRight": 124, "ArrowDown": 125, "ArrowUp": 126,
    "Delete": 117, "Home": 115, "End": 119, "PageUp": 116, "PageDown": 121,
    "F1": 122, "F2": 120, "F3": 99, "F4": 118, "F5": 96, "F6": 97, "F7": 98,
    "F8": 100, "F9": 101, "F10": 109, "F11": 103, "F12": 111,
  ]

  static func key(_ code: String, down: Bool, shift: Bool, ctrl: Bool, alt: Bool, meta: Bool) {
    guard let kc = keyMap[code] else { return } // ปุ่มที่ไม่รู้จัก = ทิ้ง ไม่เดา
    guard let ev = CGEvent(keyboardEventSource: nil, virtualKey: kc, keyDown: down) else { return }
    var flags: CGEventFlags = []
    if shift { flags.insert(.maskShift) }
    if ctrl  { flags.insert(.maskControl) }
    if alt   { flags.insert(.maskAlternate) }
    if meta  { flags.insert(.maskCommand) }
    ev.flags = flags
    ev.setIntegerValueField(.eventSourceUserData, value: kMyarapInjectedTag)
    ev.post(tap: .cghidEventTap)
  }
}


enum RemoteConsent {
  // banner windows — หนึ่งอันต่อหนึ่งจอ (ผู้ใช้หลายจอ: จอที่ถูก capture อาจไม่ใช่จอที่กำลังมอง
  // — เจอจริง: banner บน NSScreen.main จอเดียว โผล่ในภาพ Remote แต่ user มองอีกจอไม่เห็น)
  static var indicatorWindows: [NSWindow] = []
  static let disconnectTarget = RemoteDisconnectTarget() // retain เพื่อให้ปุ่มเรียกได้

  // ── ตัวจับเวลา ────────────────────────────────────────────────────────────
  // ผู้ใช้ต้องรู้ว่า "ถูกดูมานานแค่ไหนแล้ว" ไม่ใช่แค่ว่ากำลังถูกดู — แถบที่ไม่มีเวลา
  // ทำให้แยกไม่ออกระหว่างเพิ่งเริ่มกับค้างมาครึ่งชั่วโมง
  static var indicatorTimeLabels: [NSTextField] = []
  static var indicatorTimer: Timer?
  /// เวลาเริ่ม session — **ไม่รีเซ็ตตอนอัปเกรดจาก "ดู" เป็น "ควบคุม"** เพราะสิ่งที่ผู้ใช้
  /// อยากรู้คือถูกยุ่งกับเครื่องมานานแค่ไหนทั้งหมด ไม่ใช่นับใหม่ทุกครั้งที่เปลี่ยนโหมด
  static var indicatorStartedAt: Date?

  // ── ทางออกฉุกเฉิน: กด Esc ค้าง 2 วินาที ──────────────────────────────────
  // เฉพาะตอน **ถูกควบคุม** — ปุ่ม "หยุด" ต้องใช้เมาส์ ซึ่งตอนนั้นเมาส์อยู่ในมือคนอื่น
  static var escMonitor: Any?
  static var escDeadline: Timer?
  private static let kEscKeyCode: UInt16 = 53
  private static let kEscHoldSeconds: TimeInterval = 2.0

  // ถาม consent — คืน true = อนุญาต, false = ปฏิเสธ (modal, ต้องรันบน main thread)
  static func ask(viewer: String, result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      NSApp.activate(ignoringOtherApps: true) // ดึงแอปขึ้นหน้าเพื่อให้ผู้ใช้เห็น dialog
      let alert = NSAlert()
      alert.messageText = "คำขอเข้าดูหน้าจอ"
      alert.informativeText = "ผู้ดูแลระบบ \"\(viewer)\" ขอเข้าดูหน้าจอของคุณ (ดูอย่างเดียว ควบคุมไม่ได้)\n\nอนุญาตหรือไม่?"
      alert.alertStyle = .warning
      alert.addButton(withTitle: "อนุญาต")
      alert.addButton(withTitle: "ปฏิเสธ")
      let resp = alert.runModal()
      result(resp == .alertFirstButtonReturn) // ปุ่มแรก = อนุญาต
    }
  }

  /// consent สำหรับ **การควบคุม** (เมาส์/คีย์บอร์ด) — แยกจาก ask() ที่เป็นการยินยอมให้ "ดู"
  ///
  /// 🔴 นี่คือจุดบังคับจริงเพียงจุดเดียวของทั้งระบบ — input วิ่ง P2P ผ่าน WebRTC data channel
  /// ที่ backend มองไม่เห็นและบล็อกไม่ได้ ถ้าผู้ใช้ตรงนี้กดปฏิเสธ = คุมไม่ได้จริง ๆ
  static func askControl(viewer: String, result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      NSApp.activate(ignoringOtherApps: true)
      let alert = NSAlert()
      alert.messageText = "คำขอควบคุมเครื่องของคุณ"
      // ⚠️ ห้ามใส่ `**...**` — NSAlert ไม่ render markdown จะโชว์ดอกจันดิบ ๆ ให้ผู้ใช้เห็น
      alert.informativeText = "ผู้ดูแลระบบ \"\(viewer)\" ขอควบคุมเมาส์และคีย์บอร์ดของเครื่องนี้\n\n"
        + "ต่างจากการดูหน้าจอ — เมื่ออนุญาตแล้วเขาจะคลิกและพิมพ์บนเครื่องคุณได้จริง\n\n"
        + "หยุดได้ทุกเมื่อ: กดปุ่ม “หยุด” บนแถบด้านบนจอ "
        // ต้องบอกไว้ตรงนี้ ตอนที่ยังกดเมาส์เองได้ — พอถูกคุมแล้วเมาส์อยู่ในมือคนอื่น
        // ถ้าไม่เคยรู้ว่ามีทางลัดนี้ ก็จะไม่มีทางหาเจอตอนที่ต้องใช้จริง
        + "หรือกด Esc ค้าง 2 วินาที ถ้าเมาส์ใช้ไม่ได้"
      alert.alertStyle = .critical  // critical ไม่ใช่ warning — ความเสี่ยงสูงกว่าการดูเฉย ๆ
      alert.addButton(withTitle: "อนุญาตให้ควบคุม")
      alert.addButton(withTitle: "ปฏิเสธ")
      let resp = alert.runModal()
      result(resp == .alertFirstButtonReturn)
    }
  }

  // แถบลอยด้านบน "ทุกจอ" (always-on-top) + ปุ่ม "หยุด" ให้ผู้ใช้ตัดการถูกดูเองได้
  //
  // สีแยกตามความรุนแรง: **ฟ้าเขียว = ถูกดู** · **แดง = ถูกควบคุม** — เดิมแดงเหมือนกันทั้งคู่
  // ผู้ใช้จึงแยกไม่ออกว่าตอนนี้แค่ถูกมองอยู่ หรือมีคนกำลังคลิกและพิมพ์บนเครื่องจริง ๆ
  static func showIndicator(viewer: String, controlling: Bool = false) {
    DispatchQueue.main.async {
      let hadSession = indicatorStartedAt != nil
      teardownIndicator()
      if !hadSession { indicatorStartedAt = Date() } // เริ่มนับใหม่เฉพาะ session ใหม่จริง ๆ
      dlog("[MYARAP-RD] showIndicator screens=\(NSScreen.screens.count) controlling=\(controlling)")
      for screen in NSScreen.screens {
        dlog("[MYARAP-RD] banner on screen frame=\(screen.frame)")
        indicatorWindows.append(makeBanner(on: screen, viewer: viewer, controlling: controlling))
      }
      dlog("[MYARAP-RD] banners created=\(indicatorWindows.count)")

      indicatorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in tickIndicator() }
      // .common ไม่งั้นเวลาจะหยุดเดินตอนผู้ใช้ลากหน้าต่าง/เปิดเมนู (run loop เปลี่ยน mode)
      RunLoop.main.add(indicatorTimer!, forMode: .common)
      tickIndicator()

      if controlling { startEscWatch() }
    }
  }

  private static func tickIndicator() {
    guard let start = indicatorStartedAt else { return }
    let s = Int(Date().timeIntervalSince(start))
    let text = String(format: "%02d:%02d", s / 60, s % 60)
    for l in indicatorTimeLabels { l.stringValue = text }
  }

  /// วาง label ให้อยู่กึ่งกลางแนวตั้งของแถบ
  ///
  /// AppKit ไม่มี vertical-align ให้ NSTextField — ถ้ากรอบสูงกว่าบรรทัด ตัวอักษรจะชิดบนเสมอ
  /// จึงต้องวัดความสูงจริงของบรรทัดก่อน (`fittingSize` = ความสูงตามฟอนต์ที่ตั้งไว้ รวมส่วน
  /// ที่ไทยใช้วางสระบน/ล่าง) แล้วค่อยคำนวณ y เอง
  private static func centerVertically(_ field: NSTextField, x: CGFloat, width: CGFloat, in h: CGFloat) {
    field.frame = NSRect(x: x, y: 0, width: width, height: h)
    let lineH = field.fittingSize.height
    field.frame = NSRect(x: x, y: (h - lineH) / 2, width: width, height: lineH)
  }

  private static func makeBanner(on screen: NSScreen, viewer: String, controlling: Bool = false) -> NSWindow {
    let w: CGFloat = 470, h: CGFloat = 40
    let x = screen.frame.midX - w / 2
    let y = screen.frame.maxY - h - 8 // ชิดบนใต้ menu bar ของจอนั้น
    let win = NSWindow(contentRect: NSRect(x: x, y: y, width: w, height: h),
                       styleMask: .borderless, backing: .buffered, defer: false)
    win.level = .statusBar // อยู่เหนือทุกหน้าต่าง (แม้ fullscreen อื่น)
    win.isOpaque = false
    win.backgroundColor = .clear
    win.ignoresMouseEvents = false // ต้องรับคลิกเพื่อกดปุ่มหยุด
    win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    // เงาใต้แถบ (design: box-shadow 0 8px 22px -12px) — ต้องอยู่ที่ระดับ **หน้าต่าง**
    // เพราะ container ตั้ง masksToBounds เพื่อ clip gradient ซึ่ง clip เงาไปด้วย
    win.hasShadow = true

    // สีหลักของโหมด — ใช้ทั้งพื้นไล่สีและสีตัวอักษรบนปุ่ม "หยุด"
    let accent = controlling
      ? NSColor(srgbRed: 0.70, green: 0.13, blue: 0.25, alpha: 1)   // #b3213f
      : NSColor(srgbRed: 0.11, green: 0.56, blue: 0.64, alpha: 1)   // #1b8fa3
    let accent2 = controlling
      ? NSColor(srgbRed: 0.82, green: 0.23, blue: 0.36, alpha: 1)   // #d13a5c
      : NSColor(srgbRed: 0.25, green: 0.71, blue: 0.79, alpha: 1)   // #3fb6c9

    let container = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
    container.wantsLayer = true
    container.layer?.cornerRadius = 9
    container.layer?.masksToBounds = true

    let grad = CAGradientLayer()
    grad.frame = container.bounds
    grad.startPoint = CGPoint(x: 0, y: 0.5)
    grad.endPoint = CGPoint(x: 1, y: 0.5)
    grad.colors = [accent.withAlphaComponent(0.97).cgColor,
                   accent2.withAlphaComponent(0.97).cgColor]
    container.layer?.addSublayer(grad)

    // จุดขาวมีวงแหวนจาง ๆ รอบ (design: box-shadow 0 0 0 3px rgba(255,255,255,.28))
    // ทำให้จุดอ่านออกบนพื้นไล่สี ไม่จมหายไปกับพื้น
    let dot = NSView(frame: NSRect(x: 15, y: h / 2 - 3.5, width: 7, height: 7))
    dot.wantsLayer = true
    dot.layer?.backgroundColor = NSColor.white.cgColor
    dot.layer?.cornerRadius = 3.5
    dot.layer?.shadowColor = NSColor.white.cgColor
    dot.layer?.shadowOpacity = 0.28
    dot.layer?.shadowRadius = 0
    dot.layer?.shadowOffset = .zero
    // เงาแบบ "วงแหวน" ต้องกำหนด path เอง (ขยายกรอบออก 3px) — shadowRadius ให้ขอบฟุ้ง ไม่ใช่วงแหวนคม
    dot.layer?.shadowPath = CGPath(ellipseIn: CGRect(x: -3, y: -3, width: 13, height: 13), transform: nil)
    container.addSubview(dot)

    // ชื่อคนดู **หนา** ส่วนคำอธิบายน้ำหนักปกติ — ให้สายตาจับ "ใคร" ได้ก่อน "กำลังทำอะไร"
    // ⚠️ ห้ามใส่ `**...**` — NSTextField ไม่ render markdown มันจะโชว์ดอกจันดิบ ๆ (บั๊กเดิม)
    let tail = controlling
      ? " กำลังควบคุมเมาส์และคีย์บอร์ดของเครื่องนี้"
      : " กำลังดูหน้าจอของคุณ"
    let msg = NSMutableAttributedString(
      string: viewer,
      attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .bold),
                   .foregroundColor: NSColor.white])
    msg.append(NSAttributedString(
      string: tail,
      attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .regular),
                   .foregroundColor: NSColor.white]))

    let label = NSTextField(labelWithString: "")
    label.attributedStringValue = msg
    label.alignment = .left
    label.backgroundColor = .clear
    label.isBezeled = false
    label.isEditable = false
    label.lineBreakMode = .byTruncatingTail
    // ⚠️ NSTextField วาดตัวอักษร **ชิดบน** ของกรอบ ไม่ได้จัดกึ่งกลางแนวตั้งให้
    // ตั้ง frame สูงเท่าแถบ (40) ตัวหนังสือจะลอยขึ้นบน — ต้องย่อกรอบเท่าความสูงจริง
    // ของบรรทัดแล้ววางกึ่งกลางเอง (ดู centerVertically)
    centerVertically(label, x: 31, width: w - 176, in: h)
    container.addSubview(label)

    let time = NSTextField(labelWithString: "00:00")
    time.alignment = .right
    time.textColor = NSColor.white.withAlphaComponent(0.85)
    // ตัวเลขความกว้างเท่ากัน ไม่งั้นแถบจะขยับซ้ายขวาทุกวินาทีตามความกว้างของเลข
    time.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    time.backgroundColor = .clear
    time.isBezeled = false
    time.isEditable = false
    centerVertically(time, x: w - 145, width: 44, in: h)
    container.addSubview(time)
    indicatorTimeLabels.append(time)

    // ปุ่มขาวตัวอักษรสีเดียวกับแถบ (design) — ปุ่มเทามาตรฐานของ macOS จมหายไปกับพื้นไล่สี
    // จนผู้ใช้ไม่เห็นว่ามีทางออก ซึ่งเป็นสิ่งเดียวในแถบนี้ที่ต้องกดติดตั้งแต่ครั้งแรก
    let btn = NSButton(frame: NSRect(x: w - 92, y: 7, width: 80, height: 26))
    btn.isBordered = false
    btn.wantsLayer = true
    btn.layer?.backgroundColor = NSColor.white.cgColor
    btn.layer?.cornerRadius = 6
    btn.attributedTitle = NSAttributedString(
      string: "หยุด",
      attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                   .foregroundColor: accent])
    btn.target = disconnectTarget
    btn.action = #selector(RemoteDisconnectTarget.tapped)
    btn.keyEquivalent = ""
    container.addSubview(btn)

    win.contentView = container
    win.orderFrontRegardless()
    return win
  }

  // ── Esc ค้าง 2 วินาที = หยุดทันที ────────────────────────────────────────
  //
  // global monitor **ดักได้อย่างเดียว บล็อกไม่ได้** — Esc จะยังวิ่งไปถึงแอปที่ focus อยู่ด้วย
  // ยอมรับได้ เพราะนี่คือทางออกฉุกเฉิน ไม่ใช่ shortcut ที่ใช้ประจำ
  //
  // ต้องมีสิทธิ์ Accessibility ซึ่ง**ได้มาแล้วแน่นอนตอนนี้** — การควบคุมใช้ CGEventPost
  // ที่ต้องการสิทธิ์เดียวกัน ถ้าไม่ได้ก็คุมไม่ได้ตั้งแต่แรก
  private static func startEscWatch() {
    stopEscWatch()
    escMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { ev in
      guard ev.keyCode == kEscKeyCode else { return }
      // ข้าม event ที่เรายิงเข้าไปเอง — ไม่งั้นแอดมินกด Esc ค้างในโปรแกรมฝั่งนี้แล้ว
      // session ตัดตัวเองทิ้งโดยเจ้าของเครื่องไม่ได้ทำอะไรเลย
      if ev.cgEvent?.getIntegerValueField(.eventSourceUserData) == kMyarapInjectedTag { return }
      if ev.type == .keyDown {
        guard escDeadline == nil else { return } // กดค้าง = keyDown ซ้ำ ๆ อย่านับใหม่
        escDeadline = Timer.scheduledTimer(withTimeInterval: kEscHoldSeconds, repeats: false) { _ in
          dlog("[MYARAP-RD] esc-hold → disconnect")
          stopEscWatch()
          disconnectTarget.tapped()
        }
      } else {
        escDeadline?.invalidate()
        escDeadline = nil
      }
    }
  }

  private static func stopEscWatch() {
    escDeadline?.invalidate()
    escDeadline = nil
    if let m = escMonitor { NSEvent.removeMonitor(m) }
    escMonitor = nil
  }

  /// จบ session จริง — ล้างเวลาเริ่มด้วย (ต่างจาก teardown ที่ใช้ตอนสร้างแถบใหม่)
  static func hideIndicator() {
    DispatchQueue.main.async {
      teardownIndicator()
      indicatorStartedAt = nil
    }
  }

  /// รื้อแถบ+timer+monitor แต่ **คงเวลาเริ่มไว้** เพื่อให้สลับ ดู→ควบคุม แล้วเวลาเดินต่อ
  private static func teardownIndicator() {
    indicatorTimer?.invalidate()
    indicatorTimer = nil
    indicatorTimeLabels.removeAll()
    stopEscWatch()
    for win in indicatorWindows { win.orderOut(nil) }
    indicatorWindows.removeAll()
  }
}

// Stream handler: ส่ง event เมื่อ frontmost app เปลี่ยน (NSWorkspace notification)
class AppEventStreamHandler: NSObject, FlutterStreamHandler {
  private var observer: NSObjectProtocol?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    observer = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { notification in
      let app = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
        .localizedName ?? ""
      if !app.isEmpty {
        events(["event": "appChanged", "app": app])
      }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let obs = observer {
      NSWorkspace.shared.notificationCenter.removeObserver(obs)
    }
    observer = nil
    return nil
  }
}

// USB block guard: ใช้ DiskArbitration mount-approval callback ปฏิเสธการ mount ของ external USB
// volume ตั้งแต่ต้น (ก่อนจะขึ้น Finder เลย) แทนการปล่อย mount แล้วค่อย eject ทีหลัง
//
// ⚠️ ประวัติ: เวอร์ชันแรกใช้ DARegisterDiskAppearedCallback + DADiskEject (ejectหลัง disk ปรากฏ)
// — ทดสอบบนเครื่องจริงแล้วพบว่า "แพ้ race" กับ macOS automount daemon: eject สำเร็จตอนนั้น
// แต่ตัว USB ยังเสียบอยู่จริง ระบบเลย mount กลับมาใหม่เกือบทันที (เห็น "Disk" ใน Finder เหมือนเดิม)
// แก้เป็น DARegisterDiskMountApprovalCallback ซึ่งเป็น API ที่ถูกออกแบบมาสำหรับ "veto mount"
// โดยเฉพาะ — คืน DADissenter (ไม่ nil) = ปฏิเสธ mount ทันที ก่อน volume จะปรากฏใน Finder เลย
class UsbEventStreamHandler: NSObject, FlutterStreamHandler {
  // session เป็น static เพราะ MethodChannel handler (ใน awakeFromNib) เรียก eject/mount-now
  // แบบ static โดยไม่มี instance ของ class นี้อยู่ในมือ — ต้อง share session เดียวกัน
  private static var session: DASession?

  // true = ห้ามใช้ USB storage (ปฏิเสธการ mount ทุก volume ที่เข้าเงื่อนไข) — Flutter set ผ่าน MethodChannel
  static var blockingEnabled: Bool = false
  private static var eventSink: FlutterEventSink?
  // BSD name ของ disk ที่ถูก unmount เพราะ policy บล็อก (ไม่ใช่ user เพิ่งถอดเอง) — ใช้ตอน unblock
  // เพื่อพยายาม mount กลับมาให้ทันทีโดยไม่ต้องถอด-เสียบใหม่
  private static var blockedBsdNames: Set<String> = []

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    UsbEventStreamHandler.eventSink = events
    guard let session = DASessionCreate(kCFAllocatorDefault) else { return nil }
    UsbEventStreamHandler.session = session
    DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    DARegisterDiskMountApprovalCallback(session, nil, { disk, _ in
      return UsbEventStreamHandler.handleMountApproval(disk)
    }, nil)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let session = UsbEventStreamHandler.session {
      DASessionUnscheduleFromRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }
    UsbEventStreamHandler.session = nil
    UsbEventStreamHandler.eventSink = nil
    return nil
  }

  private static func isRemovableUsb(_ desc: [String: Any]) -> Bool {
    let removable = desc[kDADiskDescriptionMediaRemovableKey as String] as? Bool ?? false
    guard removable else { return false }
    let protocolName = (desc[kDADiskDescriptionDeviceProtocolKey as String] as? String) ?? ""
    return protocolName.uppercased().contains("USB")
  }

  private static func diskName(_ desc: [String: Any]) -> String {
    (desc[kDADiskDescriptionVolumeNameKey as String] as? String)
      ?? (desc[kDADiskDescriptionMediaNameKey as String] as? String)
      ?? "USB Drive"
  }

  // เรียกทุกครั้งที่ระบบกำลังจะ mount volume ใหม่ — คืน dissenter (ไม่ nil) เพื่อ "ปฏิเสธ" การ mount นั้น
  static func handleMountApproval(_ disk: DADisk) -> Unmanaged<DADissenter>? {
    guard blockingEnabled else { return nil }
    guard let desc = DADiskCopyDescription(disk) as? [String: Any] else { return nil }
    guard isRemovableUsb(desc) else { return nil }

    eventSink?(["event": "usbBlocked", "device": diskName(desc)])

    let dissenter = DADissenterCreate(kCFAllocatorDefault, DAReturn(kDAReturnNotPermitted), "Blocked by MYARAP USB policy" as CFString)
    return Unmanaged.passRetained(dissenter)
  }

  // ── Sync ทันทีตอน policy เปลี่ยน (ไม่ใช่แค่ veto การ mount ครั้งถัดไป) ─────
  //
  // mount-approval callback ด้านบนจัดการเฉพาะ "การ mount ครั้งใหม่" เท่านั้น — ถ้า USB
  // ถูกเสียบ+mount ไว้อยู่แล้วก่อนเปลี่ยน policy เป็น block, drive จะยังค้างอยู่ใน Finder
  // จนกว่าจะมีการ mount ใหม่เกิดขึ้น — ต้อง active unmount ทันทีตอน policy เปลี่ยนด้วย
  //
  // ⚠️ ประวัติ: เวอร์ชันแรกลอง shell out ไปที่ `diskutil eject`/`diskutil mountDisk` ผ่าน
  // Process — ทดสอบแล้วพบว่า **ไม่ทำงานเงียบๆ เลย** เพราะแอปนี้รัน App Sandbox
  // (`com.apple.security.app-sandbox=true` ใน DebugProfile/Release.entitlements) ซึ่งห้าม spawn
  // subprocess ใดๆ — `Process.run()` throw แล้วโดน `catch {}` กลืน error เงียบๆ พอดี ดูเหมือนไม่มี
  // อะไรเกิดขึ้นแต่จริงๆคือทุก eject/mount เรียกไม่สำเร็จสักครั้ง แก้เป็นเรียก DiskArbitration
  // framework API ตรงๆ แทน (DADiskUnmount/DADiskMount) เพราะเป็น framework call ไม่ใช่ subprocess
  // — ใช้งานได้ภายใต้ sandbox (เหมือน mount-approval callback ที่ทดสอบผ่านแล้วก่อนหน้านี้)
  //
  // ใช้ FileManager.mountedVolumeURLs() หา volume ที่ mount อยู่ปัจจุบัน (ไม่มี DiskArbitration
  // API สำหรับ "enumerate disk ทั้งหมดที่ต่ออยู่" ตรงๆ ต้องอาศัย mounted-volume list แทน)
  private static func mountedUsbDisks() -> [(disk: DADisk, name: String, bsdName: String)] {
    guard let session = session else {
      dlog("[MYARAP-USB] mountedUsbDisks: session is nil")
      return []
    }
    guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) else {
      dlog("[MYARAP-USB] mountedUsbDisks: mountedVolumeURLs returned nil")
      return []
    }
    dlog("[MYARAP-USB] mountedUsbDisks: found \(urls.count) volume urls: \(urls)")
    var out: [(disk: DADisk, name: String, bsdName: String)] = []
    for url in urls {
      guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL) else {
        dlog("[MYARAP-USB] DADiskCreateFromVolumePath failed for \(url)")
        continue
      }
      guard let desc = DADiskCopyDescription(disk) as? [String: Any] else {
        dlog("[MYARAP-USB] DADiskCopyDescription failed for \(url)")
        continue
      }
      let removable = desc[kDADiskDescriptionMediaRemovableKey as String] as? Bool ?? false
      let protocolName = (desc[kDADiskDescriptionDeviceProtocolKey as String] as? String) ?? ""
      dlog("[MYARAP-USB] disk at \(url): removable=\(removable) protocol=\(protocolName)")
      guard isRemovableUsb(desc) else { continue }
      let bsdName = (desc[kDADiskDescriptionMediaBSDNameKey as String] as? String) ?? ""
      out.append((disk: disk, name: diskName(desc), bsdName: bsdName))
    }
    return out
  }

  // Block เปิดใช้งาน — unmount USB removable ที่ mount อยู่แล้วทันที (ไม่ใช้ DADiskEject เพราะ
  // eject ตัดการเชื่อมต่อระดับ bus จริง ทำให้ mount กลับตอน unblock ไม่ได้ถ้าไม่ถอด-เสียบใหม่ —
  // แค่ unmount พอ เพราะ mount-approval callback จะกัน auto-remount ของระบบไว้อยู่แล้วตราบใดที่
  // blockingEnabled=true)
  static func ejectAllMatchingDisksNow() {
    let disks = mountedUsbDisks()
    dlog("[MYARAP-USB] ejectAllMatchingDisksNow: matched \(disks.count) disks")
    for (disk, name, bsdName) in disks {
      dlog("[MYARAP-USB] unmounting \(name) (\(bsdName))")
      DADiskUnmount(disk, DADiskUnmountOptions(kDADiskUnmountOptionForce), { disk, dissenter, _ in
        if let dissenter = dissenter {
          let status = DADissenterGetStatus(dissenter)
          dlog("[MYARAP-USB] DADiskUnmount DENIED status=\(status)")
        } else {
          dlog("[MYARAP-USB] DADiskUnmount succeeded")
        }
      }, nil)
      if !bsdName.isEmpty { blockedBsdNames.insert(bsdName) }
      let sink = eventSink
      DispatchQueue.main.async { sink?(["event": "usbBlocked", "device": name]) }
    }
  }

  // Unblock เปิดใช้งาน — แค่ clear veto (blockingEnabled=false ตั้งไว้ก่อนเรียกฟังก์ชันนี้แล้ว
  // ใน MainFlutterWindow.swift's setAllowUsb handler) ไม่พยายาม mount กลับให้อัตโนมัติ
  //
  // ⚠️ ทดสอบบนเครื่องจริงแล้วพบว่า mount กลับอัตโนมัติทำไม่ได้จริง: DADiskMount คืน
  // kDAReturnNotPrivileged (status -119930871) เสมอ — แอปทั่วไป (sandbox หรือไม่ก็ตาม) ไม่มีสิทธิ์
  // สั่ง mount disk เองโดยไม่ผ่าน privileged helper/admin authorization, และ macOS เองก็ไม่ auto
  // remount disk ที่ unmount ไว้เฉยๆ (ต่างจาก disk ที่เพิ่งเสียบใหม่) ด้วยตัวเองเช่นกัน — ตัดสินใจ
  // ร่วมกับ user แล้ว (2026-07-15): ไม่ทำ privileged-mount prompt เพราะต้องปิด App Sandbox ทั้งแอป
  // (ผลกระทบกว้างกว่าแค่ USB feature) — ยอมรับพฤติกรรมนี้แทน: ผู้ใช้ถอด-เสียบใหม่ หรือ admin mount
  // เองผ่าน Finder/Disk Utility เพื่อให้ drive กลับมาใช้ได้ทันทีหลัง unblock
  static func mountAllMatchingDisksNow() {
    dlog("[MYARAP-USB] mountAllMatchingDisksNow: veto cleared, waiting for user replug or manual mount (blockedBsdNames=\(blockedBsdNames))")
    blockedBsdNames.removeAll()
  }
}

class MainFlutterWindow: NSWindow {

  // Shared channel so AppDelegate can invoke Flutter methods
  static var windowChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // UI แบบคอนโซล (เมนูซ้าย + รายการ + รายละเอียด) ต้องการความกว้างขั้นต่ำ —
    // ย่อกว่านี้แผงรายละเอียดจะแคบจนอ่านไม่ได้ ไม่ใช่แค่ดูอึดอัด
    self.contentMinSize = NSSize(width: 1024, height: 640)

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

    // App event stream (Swift → Flutter): แจ้ง Flutter เมื่อ frontmost app เปลี่ยน
    let appEventChannel = FlutterEventChannel(name: "com.myarap/app_events", binaryMessenger: messenger)
    appEventChannel.setStreamHandler(AppEventStreamHandler())

    // USB control channel (Flutter → Swift): toggle การบล็อก USB ตาม policy ปัจจุบัน
    let usbControlChannel = FlutterMethodChannel(name: "com.myarap/usb_control", binaryMessenger: messenger)
    usbControlChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "setAllowUsb":
        let args = call.arguments as? [String: Any]
        let allow = args?["allow"] as? Bool ?? true
        dlog("[MYARAP-USB] setAllowUsb called with allow=\(allow)")
        UsbEventStreamHandler.blockingEnabled = !allow
        // sync ทันที (ไม่ใช่แค่รอ mount ครั้งถัดไป) — เรียกบน main thread ตรงๆ เพราะ DASession
        // ผูกกับ main run loop อยู่แล้ว (DASessionScheduleWithRunLoop ใช้ CFRunLoopGetMain())
        if allow {
          UsbEventStreamHandler.mountAllMatchingDisksNow()
        } else {
          UsbEventStreamHandler.ejectAllMatchingDisksNow()
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // USB block event stream (Swift → Flutter): แจ้งเมื่อ agent eject USB drive ที่ถูกบล็อก
    let usbEventChannel = FlutterEventChannel(name: "com.myarap/usb_events", binaryMessenger: messenger)
    usbEventChannel.setStreamHandler(UsbEventStreamHandler())

    // Remote event stream (Swift → Flutter): ผู้ใช้กด "หยุด" บน indicator → แจ้ง Flutter ตัด session
    let remoteEventChannel = FlutterEventChannel(name: "com.myarap/remote_events", binaryMessenger: messenger)
    remoteEventChannel.setStreamHandler(RemoteEventStreamHandler())

    // Remote Desktop channel (Flutter → Swift): capture หน้าจอ → JPEG data URL (view-only)
    let remoteChannel = FlutterMethodChannel(name: "com.myarap/remote", binaryMessenger: messenger)
    remoteChannel.setMethodCallHandler { call, result in
      if call.method != "captureScreen" { // captureScreen ถี่เกิน ไม่ log
        dlog("[MYARAP-RD] channel call: \(call.method)")
      }
      switch call.method {
      case "startCapture":
        // เริ่ม SCStream (indicator ม่วงขึ้น) — macOS 12.3+; OS เก่ากว่าใช้ one-shot fallback
        let args = call.arguments as? [String: Any]
        let maxW = args?["maxWidth"] as? Int ?? 1920
        let quality = args?["quality"] as? Double ?? 1.0
        if #available(macOS 12.3, *) {
          RemoteCapture.shared.start(maxWidth: maxW, quality: quality)
        }
        result(nil)
      case "stopCapture":
        // หยุด SCStream → macOS ปิด screen-recording indicator ทันที
        if #available(macOS 12.3, *) {
          RemoteCapture.shared.stop()
        }
        result(nil)
      case "captureScreen":
        let args = call.arguments as? [String: Any]
        let maxW = args?["maxWidth"] as? Int ?? 1920
        let quality = args?["quality"] as? Double ?? 1.0
        // ถ้า SCStream กำลังรัน คืนเฟรมล่าสุด (indicator คุมโดย stream); ไม่งั้น one-shot fallback
        if #available(macOS 12.3, *), RemoteCapture.shared.running {
          result(RemoteCapture.shared.latestFrameDataURL())
        } else {
          ScreenCapture.capture(maxWidth: maxW, quality: quality, result: result)
        }
      case "requestConsent":
        let args = call.arguments as? [String: Any]
        let viewer = args?["viewer"] as? String ?? "ผู้ดูแลระบบ"
        RemoteConsent.ask(viewer: viewer, result: result)
      case "requestControlConsent":
        let args = call.arguments as? [String: Any]
        let viewer = args?["viewer"] as? String ?? "ผู้ดูแลระบบ"
        RemoteConsent.askControl(viewer: viewer, result: result)
      case "showIndicator":
        let args = call.arguments as? [String: Any]
        RemoteConsent.showIndicator(viewer: args?["viewer"] as? String ?? "",
                                    controlling: args?["controlling"] as? Bool ?? false)
        result(nil)
      case "hideIndicator":
        RemoteConsent.hideIndicator()
        result(nil)
      // ── Remote Control (POC) — ยิง input เข้าระบบจริง ──
      // แยกเป็น method ย่อยแทนที่จะรับ payload ก้อนเดียว เพื่อให้ฝั่ง Dart อ่านง่ายและ
      // เพิ่ม/ลด event ทีละชนิดได้โดยไม่ต้องแก้ parser ทั้งก้อน
      case "inputTrusted":
        // prompt=true → เด้ง dialog ของ macOS พาไปหน้า Accessibility (สั่งเปิดเองไม่ได้)
        let args = call.arguments as? [String: Any]
        result(RemoteInput.trusted(prompt: args?["prompt"] as? Bool ?? false))
      case "mouseMove":
        let a = call.arguments as? [String: Any]
        RemoteInput.mouseMove(a?["x"] as? Double ?? 0, a?["y"] as? Double ?? 0)
        result(nil)
      case "mouseDown":
        RemoteInput.mouseDown((call.arguments as? [String: Any])?["b"] as? Int ?? 0)
        result(nil)
      case "mouseUp":
        RemoteInput.mouseUp((call.arguments as? [String: Any])?["b"] as? Int ?? 0)
        result(nil)
      case "scroll":
        let a = call.arguments as? [String: Any]
        RemoteInput.scroll(a?["dy"] as? Int ?? 0, a?["dx"] as? Int ?? 0)
        result(nil)
      case "key":
        let a = call.arguments as? [String: Any]
        RemoteInput.key(a?["c"] as? String ?? "", down: a?["down"] as? Bool ?? false,
                        shift: a?["s"] as? Bool ?? false, ctrl: a?["ctrl"] as? Bool ?? false,
                        alt: a?["alt"] as? Bool ?? false, meta: a?["meta"] as? Bool ?? false)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Activity Monitor card (Asset Detail): CPU/Memory/Energy/Disk/Network — native, sandbox-safe
    let metricsChannel = FlutterMethodChannel(name: "com.myarap/metrics", binaryMessenger: messenger)
    metricsChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "collect":
        SystemMetrics.collect { data in result(data) }
      case "location":
        LocationProvider.shared.requestLocation { coord in
          if let c = coord {
            result(["lat": c.latitude, "lng": c.longitude])
          } else {
            result(nil)
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

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
