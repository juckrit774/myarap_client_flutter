import Cocoa
import FlutterMacOS
import DiskArbitration
import ScreenCaptureKit
import CoreMedia
import CoreImage

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
  private var maxWidth: Int = 1280
  private var quality: Double = 0.5
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
enum RemoteConsent {
  // floating banner window แสดง "🔴 หน้าจอกำลังถูกดู" + ปุ่มหยุด ตลอดที่มี session
  static var indicatorWindow: NSWindow?
  static let disconnectTarget = RemoteDisconnectTarget() // retain เพื่อให้ปุ่มเรียกได้

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

  // แสดง banner แดงลอยด้านบนจอ (always-on-top) + ปุ่ม "หยุด" ให้ผู้ใช้ตัดการถูกดูเองได้
  static func showIndicator(viewer: String) {
    DispatchQueue.main.async {
      hideIndicatorNow()
      guard let screen = NSScreen.main else { return }
      let w: CGFloat = 440, h: CGFloat = 40
      let x = screen.frame.midX - w / 2
      let y = screen.frame.maxY - h - 8 // ชิดบนใต้ menu bar
      let win = NSWindow(contentRect: NSRect(x: x, y: y, width: w, height: h),
                         styleMask: .borderless, backing: .buffered, defer: false)
      win.level = .statusBar // อยู่เหนือทุกหน้าต่าง (แม้ fullscreen อื่น)
      win.isOpaque = false
      win.backgroundColor = .clear
      win.ignoresMouseEvents = false // ต้องรับคลิกเพื่อกดปุ่มหยุด
      win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

      let container = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
      container.wantsLayer = true
      container.layer?.backgroundColor = NSColor(calibratedRed: 0.85, green: 0.12, blue: 0.25, alpha: 0.95).cgColor
      container.layer?.cornerRadius = 8

      let label = NSTextField(labelWithString: "🔴  หน้าจอกำลังถูกดูโดย \(viewer)")
      label.frame = NSRect(x: 14, y: 0, width: w - 110, height: h)
      label.alignment = .left
      label.textColor = .white
      label.font = .systemFont(ofSize: 13, weight: .semibold)
      label.backgroundColor = .clear
      label.isBezeled = false
      label.isEditable = false
      label.lineBreakMode = .byTruncatingTail
      container.addSubview(label)

      let btn = NSButton(frame: NSRect(x: w - 92, y: 7, width: 80, height: 26))
      btn.title = "หยุด"
      btn.bezelStyle = .rounded
      btn.font = .systemFont(ofSize: 12, weight: .semibold)
      btn.target = disconnectTarget
      btn.action = #selector(RemoteDisconnectTarget.tapped)
      btn.keyEquivalent = ""
      container.addSubview(btn)

      win.contentView = container
      win.orderFrontRegardless()
      indicatorWindow = win
    }
  }

  static func hideIndicator() {
    DispatchQueue.main.async { hideIndicatorNow() }
  }

  private static func hideIndicatorNow() {
    indicatorWindow?.orderOut(nil)
    indicatorWindow = nil
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
      switch call.method {
      case "startCapture":
        // เริ่ม SCStream (indicator ม่วงขึ้น) — macOS 12.3+; OS เก่ากว่าใช้ one-shot fallback
        let args = call.arguments as? [String: Any]
        let maxW = args?["maxWidth"] as? Int ?? 1280
        let quality = args?["quality"] as? Double ?? 0.5
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
        let maxW = args?["maxWidth"] as? Int ?? 1280
        let quality = args?["quality"] as? Double ?? 0.5
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
      case "showIndicator":
        let args = call.arguments as? [String: Any]
        RemoteConsent.showIndicator(viewer: args?["viewer"] as? String ?? "")
        result(nil)
      case "hideIndicator":
        RemoteConsent.hideIndicator()
        result(nil)
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
