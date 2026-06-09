# คู่มือการติดตั้ง MyARAP

**เวอร์ชัน:** 1.0.0  
**ผู้พัฒนา:** ARSoft Mobile

---

## สารบัญ

- [ความต้องการของระบบ](#ความต้องการของระบบ)
- [การติดตั้งบน Windows](#การติดตั้งบน-windows)
- [การติดตั้งบน macOS](#การติดตั้งบน-macos)
- [การตั้งค่าครั้งแรก](#การตั้งค่าครั้งแรก)
- [การถอนการติดตั้ง](#การถอนการติดตั้ง)

---

## ความต้องการของระบบ

| รายการ | Windows | macOS |
|---|---|---|
| ระบบปฏิบัติการ | Windows 10 (64-bit) ขึ้นไป | macOS 10.15 Catalina ขึ้นไป |
| สถาปัตยกรรม | x64 | Intel / Apple Silicon (M1 ขึ้นไป) |
| RAM | 4 GB ขึ้นไป | 4 GB ขึ้นไป |
| พื้นที่ดิสก์ | 200 MB | 200 MB |
| เครือข่าย | ต้องเชื่อมต่อกับเครือข่ายภายในองค์กร | ต้องเชื่อมต่อกับเครือข่ายภายในองค์กร |

---

## การติดตั้งบน Windows

### ขั้นตอนที่ 1 — ดาวน์โหลดไฟล์ติดตั้ง

ดาวน์โหลดไฟล์ติดตั้งจากแผนก IT โดยมีให้เลือก 2 รูปแบบ

| รูปแบบ | ไฟล์ | เหมาะสำหรับ |
|---|---|---|
| EXE (แนะนำ) | `MyARAP_Setup.exe` | ติดตั้งทั่วไป มี Wizard แนะนำ |
| MSI | `MyARAP.msi` | ติดตั้งผ่าน Group Policy / Silent install |

---

### ขั้นตอนที่ 2 — อนุญาตแอปพลิเคชัน (Windows SmartScreen)

เนื่องจาก MyARAP เป็นซอฟต์แวร์ภายในองค์กรที่ไม่ได้ผ่าน Microsoft Store Windows อาจแสดงคำเตือนจาก SmartScreen

**1. คลิก "More info" (ข้อมูลเพิ่มเติม)**

![Windows SmartScreen — หน้าต่างคำเตือน "Windows protected your PC"](images/win_smartscreen_1.png)

**2. คลิกปุ่ม "Run anyway" (เรียกใช้งานต่อไป)**

![Windows SmartScreen — คลิก "More info" แล้วเห็นปุ่ม "Run anyway"](images/win_smartscreen_2.png)

---

> **หากไม่พบปุ่ม "Run anyway"** ให้ทำตามขั้นตอนด้านล่าง
>
> 1. คลิกขวาที่ไฟล์ `MyARAP_Setup.exe` → เลือก **Properties**
> 2. แท็บ **General** → หัวข้อ **Security** → ติ๊กถูก **Unblock**
> 3. คลิก **OK** แล้วเปิดไฟล์อีกครั้ง
>
> ![File Properties — ช่อง Unblock ในแท็บ General](images/win_properties_unblock.png)

---

### ขั้นตอนที่ 3 — ติดตั้งโปรแกรม (EXE)

1. ดับเบิลคลิกไฟล์ **`MyARAP_Setup.exe`**
2. หากมีหน้าต่าง **User Account Control (UAC)** ปรากฏขึ้น คลิก **Yes**

   ![User Account Control — คลิก Yes เพื่ออนุญาต](images/win_uac.png)

3. หน้าต่าง Setup Wizard จะเปิดขึ้น คลิก **Next**

   ![Setup Wizard — หน้า Welcome](images/win_installer_welcome.png)

4. อ่านและยอมรับ License Agreement แล้วคลิก **Next**
5. เลือกโฟลเดอร์ติดตั้ง (ค่าเริ่มต้น: `C:\Program Files\MyARAP`) แล้วคลิก **Next**
6. เลือกว่าต้องการสร้าง **Desktop shortcut** หรือไม่ แล้วคลิก **Next**
7. คลิก **Install** เพื่อเริ่มติดตั้ง
8. เมื่อติดตั้งเสร็จ คลิก **Finish**

   ![Setup Wizard — หน้า Installation Complete](images/win_installer_finish.png)

---

### ขั้นตอนที่ 3 — ติดตั้งโปรแกรม (MSI)

ดับเบิลคลิกไฟล์ **`MyARAP.msi`** แล้วทำตาม Wizard  
หรือติดตั้งแบบ Silent ผ่าน Command Prompt (Admin):

```cmd
msiexec /i MyARAP.msi /quiet /norestart
```

---

### การใช้งาน System Tray (Windows)

MyARAP รองรับการย่อลง System Tray แทนการปิด

![ไอคอน MyARAP ใน System Tray มุมขวาล่างของหน้าจอ](images/win_tray_icon.png)

- **กดปุ่ม Minimize (−):** โปรแกรมจะซ่อนลง System Tray
- **คลิกซ้าย** ที่ไอคอน Tray: เปิดหน้าต่างโปรแกรมขึ้นมา
- **คลิกขวา** ที่ไอคอน Tray: แสดงเมนู

  ![เมนูคลิกขวา System Tray แสดง Open และ Exit](images/win_tray_menu.png)

  - **Open** — เปิดหน้าต่างโปรแกรม
  - **Exit** — ปิดโปรแกรม

---

## การติดตั้งบน macOS

### ขั้นตอนที่ 1 — ดาวน์โหลดไฟล์ติดตั้ง

ดาวน์โหลดไฟล์ **`MyARAP.dmg`** จากแผนก IT

---

### ขั้นตอนที่ 2 — อนุญาตแอปพลิเคชันที่ไม่ได้มาจาก App Store

เนื่องจาก MyARAP เป็นซอฟต์แวร์ภายในองค์กรที่ไม่ได้ผ่าน Mac App Store macOS จะบล็อกการเปิดโปรแกรมโดยค่าเริ่มต้น

#### วิธีที่ 1 — เปิดครั้งแรกผ่านเมนูคลิกขวา (แนะนำ)

1. เปิดไฟล์ **`MyARAP.dmg`** และลาก **MyARAP.app** ไปวางใน **Applications**
2. เปิดโฟลเดอร์ **Applications** ใน Finder
3. **คลิกขวา** (หรือ Control+คลิก) ที่ **MyARAP.app** → เลือก **Open**

   ![Finder — คลิกขวาที่ MyARAP.app แล้วเลือก Open](images/mac_rightclick_open.png)

4. กล่องข้อความจะถามว่า "macOS cannot verify the developer" ให้คลิก **Open**

   ![Dialog ยืนยัน — คลิก Open เพื่อเปิดโปรแกรม](images/mac_open_confirm.png)

> หลังจากทำครั้งแรกแล้ว ครั้งต่อไปสามารถเปิดโปรแกรมได้ตามปกติ

---

#### วิธีที่ 2 — เปิดอนุญาตผ่าน System Settings

หากเปิดโปรแกรมแล้วเห็นข้อความ **"MyARAP cannot be opened because it is from an unidentified developer"**

![Dialog "MyARAP cannot be opened because it is from an unidentified developer"](images/mac_blocked_dialog.png)

**macOS Ventura (13) ขึ้นไป:**

1. เปิด  → **System Settings** → **Privacy & Security**

   ![System Settings — หน้า Privacy & Security](images/mac_system_settings.png)

2. เลื่อนลงไปที่หัวข้อ **Security** จะเห็นปุ่ม **Open Anyway**
3. คลิก **Open Anyway** แล้วกรอกรหัสผ่าน Mac

   ![ปุ่ม Open Anyway ในหน้า Privacy & Security](images/mac_open_anyway.png)

**macOS Monterey (12) หรือเก่ากว่า:**

1. เปิด  → **System Preferences** → **Security & Privacy**
2. แท็บ **General** → คลิก 🔒 แล้วกรอกรหัสผ่านเพื่อปลดล็อก
3. คลิก **Open Anyway** ที่อยู่ใต้ข้อความเตือน

---

#### วิธีที่ 3 — ใช้ Terminal (กรณีที่ปุ่มไม่ปรากฏ)

เปิด **Terminal** แล้วรันคำสั่ง:

```bash
xattr -cr /Applications/MyARAP.app
```

จากนั้นเปิดโปรแกรมได้ตามปกติ

---

### ขั้นตอนที่ 3 — ติดตั้งโปรแกรม

1. เปิดไฟล์ **`MyARAP.dmg`** โดยดับเบิลคลิก
2. หน้าต่างจะแสดง MyARAP.app และโฟลเดอร์ Applications — ลาก **MyARAP.app** ไปวางบนไอคอน **Applications**

   ![หน้าต่าง DMG — ลาก MyARAP.app ไปวางที่ Applications](images/mac_dmg_window.png)

3. รอจนคัดลอกเสร็จ แล้วปิดหน้าต่าง DMG
4. นำ DMG ออกจากระบบ: คลิกขวา DMG ใน Finder → **Eject**
5. เปิดโปรแกรมจาก **Applications** หรือ **Launchpad**

---

## การตั้งค่าครั้งแรก

เมื่อเปิดโปรแกรมครั้งแรก MyARAP จะทำการตรวจสอบตัวตนโดยอัตโนมัติจากข้อมูลฮาร์ดแวร์ของเครื่อง **ไม่ต้องกรอก Username / Password**

หากต้องการเปลี่ยน Server URL (กรณีแผนก IT แจ้งที่อยู่เซิร์ฟเวอร์ใหม่):

1. คลิกเมนู **Settings** (การตั้งค่า)
2. แก้ไข **Server URL** ให้ตรงกับที่แผนก IT กำหนด
3. คลิก **Save** แล้วรีสตาร์ทโปรแกรม

---

## การถอนการติดตั้ง

### Windows

**วิธีที่ 1 — ผ่าน Control Panel**
1. เปิด **Control Panel** → **Programs** → **Uninstall a program**
2. เลือก **MyARAP** แล้วคลิก **Uninstall**

**วิธีที่ 2 — ผ่าน Start Menu**
1. เปิด **Start Menu** → **MyARAP**
2. คลิก **Uninstall MyARAP**

### macOS

1. เปิด **Finder** → **Applications**
2. ลาก **MyARAP.app** ไปวางในถังขยะ
3. กด **Command + Delete** เพื่อล้างถังขยะ

---

## ติดต่อฝ่าย IT

หากพบปัญหาในการติดตั้งหรือใช้งาน กรุณาติดต่อแผนก IT ภายในองค์กร
