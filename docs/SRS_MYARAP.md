# Software Requirements Specification (SRS)
## ระบบ MYARAP — My Asset Reporting Application
**เวอร์ชัน:** 1.0.0  
**วันที่:** 26 พฤษภาคม 2569  
**จัดทำโดย:** ARSoft Mobile

---

## 1. บทนำ (Introduction)

### 1.1 วัตถุประสงค์
เอกสารนี้อธิบายข้อกำหนดซอฟต์แวร์ของระบบ **MYARAP** (My Asset Reporting Application) ซึ่งเป็นแอปพลิเคชันสำหรับการบริหารจัดการและตรวจสอบทรัพย์สินไอทีขององค์กร รวมถึงการแจ้งปัญหาและรับการแจ้งเตือนจากระบบ

### 1.2 ขอบเขต
MYARAP รองรับการทำงานบน **macOS** และ **Windows** โดยแอปพลิเคชันจะ:
- ดึงข้อมูลฮาร์ดแวร์และซอฟต์แวร์ของเครื่องโดยอัตโนมัติ
- ส่งข้อมูลไปยังเซิร์ฟเวอร์กลางขององค์กร
- ให้ผู้ใช้แจ้งปัญหาด้านไอที พร้อมแนบรูปภาพ
- แสดงการแจ้งเตือนจากระบบ

### 1.3 คำย่อและนิยาม
| คำ | ความหมาย |
|----|----------|
| Asset | ทรัพย์สินไอที เช่น คอมพิวเตอร์ โน้ตบุ๊ก |
| Asset No | รหัสทรัพย์สินที่ระบบกำหนด |
| Token | รหัสยืนยันตัวตนสำหรับเรียก API |
| Heartbeat | การส่งสัญญาณแสดงสถานะออนไลน์ของอุปกรณ์ตามรอบเวลา |
| SRS | Software Requirements Specification |

---

## 2. ภาพรวมระบบ (System Overview)

### 2.1 สถาปัตยกรรม
```
┌─────────────────────────────┐
│       MYARAP Client         │
│   (macOS / Windows App)     │
│                             │
│  ┌─────────┐ ┌───────────┐  │
│  │  Home   │ │  Report   │  │
│  │ Screen  │ │  Problem  │  │
│  └─────────┘ └───────────┘  │
│  ┌─────────┐ ┌───────────┐  │
│  │Notifica-│ │ Settings  │  │
│  │  tion   │ │           │  │
│  └─────────┘ └───────────┘  │
└──────────────┬──────────────┘
               │ HTTPS (REST API)
               ▼
┌─────────────────────────────┐
│     ARSoft Server           │
│  /v2/api/AssetAuthen        │
│  /v2/api/... (Web Services) │
└─────────────────────────────┘
```

### 2.2 Platform รองรับ
| Platform | เวอร์ชันขั้นต่ำ |
|----------|---------------|
| macOS | macOS 10.14 Mojave ขึ้นไป |
| Windows | Windows 10 Build 1809 ขึ้นไป |

### 2.3 Framework และ Dependencies
| Package | เวอร์ชัน | การใช้งาน |
|---------|---------|-----------|
| Flutter | 3.44.0 | UI Framework |
| Dart | 3.12.0 | ภาษาโปรแกรม |
| dio | 5.8.0 | HTTP Client |
| provider | 6.1.2 | State Management |
| shared_preferences | 2.5.3 | Local Storage |
| qr_flutter | 4.1.0 | QR Code Generation |
| device_info_plus | 10.1.0 | Device Information |
| file_picker | 8.1.3 | File/Image Selection |
| intl | 0.20.2 | Date Formatting |

---

## 3. ข้อกำหนดฟังก์ชัน (Functional Requirements)

### 3.1 FR-01: การ Authentication และ Login อัตโนมัติ

**คำอธิบาย:** แอปพลิเคชันทำการ login อัตโนมัติโดยใช้ข้อมูลอุปกรณ์ ไม่ต้องให้ผู้ใช้กรอก username/password

| ID | รายละเอียด |
|----|-----------|
| FR-01-01 | ระบบดึงข้อมูลอุปกรณ์โดยอัตโนมัติเมื่อแอปเริ่มทำงาน |
| FR-01-02 | ระบบส่ง payload ข้อมูลอุปกรณ์ไปยัง API `LoginWithClient` |
| FR-01-03 | หาก login สำเร็จ ระบบบันทึก token และข้อมูล login ลง local cache |
| FR-01-04 | หาก server ไม่ตอบสนอง ระบบใช้ข้อมูล cache ที่บันทึกไว้ก่อนหน้า |
| FR-01-05 | ระบบแสดง asset number และชื่อผู้ใช้หลัง login สำเร็จ |

**Payload ที่ส่ง:**
```json
{
  "userLogOn": "string",
  "assetNumber": "string",
  "deviceInfo": { ... },
  "network": { "publicIP": "string" },
  "fullDeviceName": "string"
}
```

---

### 3.2 FR-02: การดึงและแสดงข้อมูลอุปกรณ์

**คำอธิบาย:** ระบบดึงข้อมูลฮาร์ดแวร์และซอฟต์แวร์ของเครื่องและแสดงผล

#### 3.2.1 ข้อมูลที่ดึงบน macOS
| หมวด | ข้อมูล | วิธีดึง |
|------|--------|---------|
| Identity | Computer Name, Serial Number, UUID | Native MethodChannel (Swift) |
| Hardware | Model, Chip, Processor, Cores, Memory | Native MethodChannel |
| Storage | ชื่อ, ประเภท, ขนาด, พื้นที่ว่าง | Native MethodChannel |
| GPU | ชื่อการ์ดจอ | Native MethodChannel |
| Display | ชื่อจอ, ความละเอียด, Built-in/External | Native MethodChannel |
| OS | Version, Kernel, Boot Volume, Uptime, Firmware | Native MethodChannel |
| Network | IP Address | Native MethodChannel |
| Software | รายการแอปที่ติดตั้ง, เวอร์ชัน, ขนาด | Native MethodChannel |

#### 3.2.2 ข้อมูลที่ดึงบน Windows
| หมวด | ข้อมูล | วิธีดึง |
|------|--------|---------|
| Identity | Computer Name, Serial Number, UUID | PowerShell `Win32_BIOS`, `Win32_ComputerSystemProduct` |
| Hardware | Model, Manufacturer, Cores, Memory (GB) | PowerShell `Win32_ComputerSystem` |
| CPU | ชื่อ CPU, Architecture, Max Speed (MHz) | PowerShell `Win32_Processor` |
| Storage | ชื่อ Volume, ประเภท (SSD/HDD), ขนาด, พื้นที่ว่าง | PowerShell `Win32_LogicalDisk`, `Get-PhysicalDisk` |
| GPU | ชื่อการ์ดจอ, ความละเอียดจอ | PowerShell `Win32_VideoController` |
| Display | ชื่อ, Resolution (Width x Height) | PowerShell `Win32_VideoController` |
| OS | Caption, Version, Kernel Version | PowerShell `Win32_OperatingSystem` |
| System | Uptime, Firmware (BIOS) Version | PowerShell |
| Network | IP Address (non-loopback IPv4) | PowerShell `Get-NetIPAddress` |
| Software | รายการโปรแกรมที่ติดตั้ง (Registry) | PowerShell Registry `Uninstall\*` |

| ID | รายละเอียด |
|----|-----------|
| FR-02-01 | ระบบต้องดึงข้อมูลครบตามตารางด้านบน |
| FR-02-02 | แสดงข้อมูลแบ่งเป็นหมวดหมู่ในหน้า Home |
| FR-02-03 | กรณีข้อมูลใดดึงไม่ได้ให้แสดง "N/A" |
| FR-02-04 | ผู้ใช้กด Refresh เพื่ออัปเดตข้อมูลใหม่ได้ |

---

### 3.3 FR-03: Heartbeat และ Device Update

**คำอธิบาย:** ระบบส่งข้อมูลอุปกรณ์ไปยังเซิร์ฟเวอร์เป็นรอบตามเวลาที่กำหนด

| ID | รายละเอียด |
|----|-----------|
| FR-03-01 | หลัง login สำเร็จ ระบบเรียก API `UpdateDeviceInfo` ทันที |
| FR-03-02 | Server ส่งค่า `dueDateTime` (Unix timestamp) กลับมา |
| FR-03-03 | ระบบตั้งตัวนับเวลาส่ง heartbeat ครั้งถัดไปตาม `dueDateTime` |
| FR-03-04 | Heartbeat ส่งข้อมูล: device info, network, applications, user logon |
| FR-03-05 | หาก server ไม่ตอบสนอง ระบบข้าม heartbeat และรอรอบถัดไป |
| FR-03-06 | แสดงเวลาล่าสุดที่อัปเดตสำเร็จในหน้า Home |

---

### 3.4 FR-04: การแจ้งปัญหา (Report Problem)

**คำอธิบาย:** ผู้ใช้แจ้งปัญหาด้านไอทีพร้อมรายละเอียดและรูปภาพ

| ID | รายละเอียด |
|----|-----------|
| FR-04-01 | ระบบโหลดรายการประเภทปัญหาจาก API |
| FR-04-02 | ผู้ใช้เลือกประเภทปัญหาจาก dropdown |
| FR-04-03 | ผู้ใช้กรอกรายละเอียดปัญหา (Remark) |
| FR-04-04 | ผู้ใช้แนบรูปภาพได้สูงสุดตามที่ config กำหนด (`imageReportLimit`) |
| FR-04-05 | รูปภาพถูก upload เป็น multipart form |
| FR-04-06 | ระบบแสดงผลลัพธ์การส่ง (สำเร็จ/ไม่สำเร็จ) |
| FR-04-07 | หลังส่งสำเร็จ ระบบล้างฟอร์มให้พร้อมแจ้งปัญหาใหม่ |

---

### 3.5 FR-05: รายการปัญหาที่แจ้ง (Problem List)

**คำอธิบาย:** แสดงรายการปัญหาที่เคยแจ้งไว้

| ID | รายละเอียด |
|----|-----------|
| FR-05-01 | ระบบโหลดรายการปัญหาที่แจ้งโดย asset ปัจจุบัน |
| FR-05-02 | แสดงข้อมูล: วันที่แจ้ง, ประเภทปัญหา, รายละเอียด, สถานะ |
| FR-05-03 | ผู้ใช้กดดูรายละเอียดปัญหาแต่ละรายการได้ |
| FR-05-04 | แสดงรูปภาพที่แนบมาในรายละเอียดปัญหา |

---

### 3.6 FR-06: การแจ้งเตือน (Notification)

**คำอธิบาย:** แสดงการแจ้งเตือนจากระบบที่เกี่ยวกับ asset ของผู้ใช้

| ID | รายละเอียด |
|----|-----------|
| FR-06-01 | ระบบโหลดรายการแจ้งเตือนจาก API |
| FR-06-02 | แสดงรายการแจ้งเตือนพร้อมวันเวลา |
| FR-06-03 | ผู้ใช้กดดูรายละเอียดการแจ้งเตือนได้ |
| FR-06-04 | แสดง badge จำนวนการแจ้งเตือนใหม่ (ถ้ามี) |

---

### 3.7 FR-07: QR Code

**คำอธิบาย:** แสดง QR Code ของ token สำหรับใช้ยืนยันตัวตนในระบบอื่น

| ID | รายละเอียด |
|----|-----------|
| FR-07-01 | ผู้ใช้กดปุ่ม QR Code บน header เพื่อแสดง QR |
| FR-07-02 | QR Code encode ค่า token ของผู้ใช้ |
| FR-07-03 | หาก token ว่างเปล่า QR Code encode ค่า "MYARAP" แทน |
| FR-07-04 | แสดง QR Code เป็น dialog popup |

---

### 3.8 FR-08: การตั้งค่า (Settings)

**คำอธิบาย:** ให้ผู้ใช้กำหนด URL ของ server

| ID | รายละเอียด |
|----|-----------|
| FR-08-01 | ผู้ใช้กำหนด Server URL สำหรับเชื่อมต่อ API |
| FR-08-02 | ระบบบันทึก URL ลง local storage |
| FR-08-03 | ระบบใช้ URL ที่กำหนดในทุก API request ถัดไป |
| FR-08-04 | หากไม่กำหนด ระบบใช้ค่า default จาก `AppConfig.baseUrl` |

---

## 4. ข้อกำหนดที่ไม่ใช่ฟังก์ชัน (Non-Functional Requirements)

### 4.1 NFR-01: ประสิทธิภาพ (Performance)
| ID | รายละเอียด | เกณฑ์ |
|----|-----------|-------|
| NFR-01-01 | เวลาเริ่มต้นแอป | ≤ 3 วินาที |
| NFR-01-02 | เวลาดึงข้อมูลอุปกรณ์ | ≤ 5 วินาที |
| NFR-01-03 | Timeout การเชื่อมต่อ API | 15 วินาที |
| NFR-01-04 | Timeout รับข้อมูล API | 15 วินาที |

### 4.2 NFR-02: ความปลอดภัย (Security)
| ID | รายละเอียด |
|----|-----------|
| NFR-02-01 | การสื่อสารกับเซิร์ฟเวอร์ใช้ HTTPS |
| NFR-02-02 | รองรับ self-signed certificate สำหรับเซิร์ฟเวอร์ภายในองค์กร |
| NFR-02-03 | token ถูกเก็บใน local storage ของเครื่อง |
| NFR-02-04 | ไม่มีการเก็บ password ของผู้ใช้ |

### 4.3 NFR-03: ความน่าเชื่อถือ (Reliability)
| ID | รายละเอียด |
|----|-----------|
| NFR-03-01 | แอปต้องทำงานได้แม้ไม่มีอินเทอร์เน็ต (offline mode ด้วย cache) |
| NFR-03-02 | กรณี API ล้มเหลว แอปต้องไม่ crash |
| NFR-03-03 | ข้อมูล login ถูก cache ไว้ใช้งานแบบ offline |

### 4.4 NFR-04: ความสามารถในการใช้งาน (Usability)
| ID | รายละเอียด |
|----|-----------|
| NFR-04-01 | UI รองรับภาษาไทยและอังกฤษ |
| NFR-04-02 | ไม่ต้องกรอก username/password — login อัตโนมัติ |
| NFR-04-03 | หน้าจอแสดงผล Loading ขณะดึงข้อมูล |

### 4.5 NFR-05: การดูแลรักษา (Maintainability)
| ID | รายละเอียด |
|----|-----------|
| NFR-05-01 | โค้ดแบ่งตาม Feature-based architecture |
| NFR-05-02 | แต่ละ Feature แยก Model, ViewModel, Screen |
| NFR-05-03 | ใช้ Provider pattern สำหรับ state management |

---

## 5. สถาปัตยกรรมซอฟต์แวร์ (Software Architecture)

### 5.1 โครงสร้าง Project
```
lib/
├── core/
│   ├── config/        # AppConfig, AppColors
│   ├── models/        # Base request/response models
│   ├── services/      # NetworkManager
│   └── storage/       # CacheManager
├── features/
│   ├── auth/          # Login models
│   ├── home/          # Device info, Heartbeat
│   ├── notification/  # Notification list & detail
│   ├── problem/       # Problem list & detail
│   ├── qrcode/        # QR Code display
│   ├── report/        # Report problem
│   └── settings/      # Server URL settings
├── shared/
│   └── widgets/       # AppHeader, LoadingOverlay
└── main.dart
```

### 5.2 API Endpoints
| Endpoint | Module | Target | คำอธิบาย |
|----------|--------|--------|----------|
| `/v2/api/AssetAuthen` | Authentication | LoginWithClient | Login ด้วยข้อมูลอุปกรณ์ |
| (Web Service URL) | Asset | UpdateDeviceInfo | ส่ง heartbeat ข้อมูลอุปกรณ์ |
| (Web Service URL) | Problem | GetProblemTypes | ดึงประเภทปัญหา |
| (Web Service URL) | Problem | ReportProblem | แจ้งปัญหา |
| (Web Service URL) | Problem | GetProblems | ดึงรายการปัญหา |
| (Web Service URL) | Notification | GetNotifications | ดึงการแจ้งเตือน |

### 5.3 Data Flow — Login
```
App Start
  → ดึงข้อมูล cache (token, loginResponse)
  → ดึงข้อมูลอุปกรณ์ (DeviceDetail.collect())
  → เรียก API LoginWithClient
  → บันทึก token ลง cache
  → เรียก API UpdateDeviceInfo
  → ตั้ง Heartbeat Timer
  → แสดงหน้า Home
```

---

## 6. ข้อกำหนดอินเทอร์เฟซ (Interface Requirements)

### 6.1 หน้าจอหลัก (Home Screen)
- แสดง Asset Number และชื่อผู้ใช้
- แสดงเวลาอัปเดตล่าสุด
- แสดงข้อมูลอุปกรณ์แบ่งเป็น Card: ข้อมูลอุปกรณ์, CPU, หน่วยความจำ, Storage, GPU, จอแสดงผล, OS, เครือข่าย, แอปพลิเคชัน
- ปุ่ม: QR Code, Notifications, Settings, Refresh
- ปุ่มด้านล่าง: ปัญหาที่แจ้ง, แจ้งปัญหา

### 6.2 หน้าแจ้งปัญหา (Report Screen)
- Dropdown เลือกประเภทปัญหา
- Text field กรอกรายละเอียด
- ปุ่มเพิ่มรูปภาพ (สูงสุดตาม `imageReportLimit`)
- Preview รูปภาพที่เลือก พร้อมปุ่มลบ
- ปุ่มส่ง

### 6.3 หน้าตั้งค่า (Settings Screen)
- Text field กรอก Server URL
- ปุ่มบันทึก

---

## 7. ข้อจำกัดและสมมติฐาน (Constraints & Assumptions)

| ข้อ | รายละเอียด |
|-----|-----------|
| C-01 | แอปต้องการสิทธิ์อ่านข้อมูลระบบ (macOS: MethodChannel; Windows: PowerShell) |
| C-02 | Windows ต้องมี PowerShell 3.0+ (มีมาตั้งแต่ Windows 8) |
| C-03 | macOS ต้องมี native plugin `com.myarap/device_info` ถูก implement |
| C-04 | เซิร์ฟเวอร์ต้องรองรับ REST API format ที่กำหนด |
| A-01 | เครื่องที่ติดตั้งแอปถูก register ไว้ในระบบ MYARAP แล้ว |
| A-02 | ผู้ใช้มีสิทธิ์รัน PowerShell บน Windows |

---

## 8. ประวัติการแก้ไขเอกสาร

| เวอร์ชัน | วันที่ | ผู้แก้ไข | รายละเอียด |
|---------|--------|---------|-----------|
| 1.0.0 | 26 พ.ค. 2569 | ARSoft Mobile | สร้างเอกสารครั้งแรก |
