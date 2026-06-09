"""สร้างไฟล์ คู่มือการติดตั้ง_MyARAP.docx จากเนื้อหาคู่มือ"""
from docx import Document
from docx.shared import Pt, RGBColor, Inches, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement
import os

IMAGES_DIR = os.path.join(os.path.dirname(__file__), "images")
OUT_PATH = os.path.join(os.path.dirname(__file__), "คู่มือการติดตั้ง_MyARAP.docx")

doc = Document()

# ── Page margins ──────────────────────────────────────────────────────────────
for section in doc.sections:
    section.top_margin    = Cm(2.5)
    section.bottom_margin = Cm(2.5)
    section.left_margin   = Cm(3)
    section.right_margin  = Cm(2.5)

# ── Styles ────────────────────────────────────────────────────────────────────
styles = doc.styles

def set_font(style, name="TH Sarabun New", size=16, bold=False, color=None):
    f = style.font
    f.name = name
    f.size = Pt(size)
    f.bold = bold
    if color:
        f.color.rgb = RGBColor(*color)

set_font(styles["Normal"],   size=14)
set_font(styles["Heading 1"], size=22, bold=True, color=(0x1F, 0x49, 0x7D))
set_font(styles["Heading 2"], size=18, bold=True, color=(0x2E, 0x74, 0xB5))
set_font(styles["Heading 3"], size=16, bold=True, color=(0x2E, 0x74, 0xB5))

def add_heading(text, level):
    p = doc.add_heading(text, level=level)
    p.paragraph_format.space_before = Pt(12)
    p.paragraph_format.space_after  = Pt(4)
    return p

def add_para(text="", bold=False, italic=False, size=14, indent=0, space_before=4, space_after=4):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(space_before)
    p.paragraph_format.space_after  = Pt(space_after)
    if indent:
        p.paragraph_format.left_indent = Cm(indent)
    if text:
        run = p.add_run(text)
        run.font.name = "TH Sarabun New"
        run.font.size = Pt(size)
        run.bold   = bold
        run.italic = italic
    return p

def add_bullet(text, indent_cm=1.0):
    p = doc.add_paragraph(style="List Bullet")
    p.paragraph_format.left_indent  = Cm(indent_cm)
    p.paragraph_format.space_before = Pt(2)
    p.paragraph_format.space_after  = Pt(2)
    run = p.add_run(text)
    run.font.name = "TH Sarabun New"
    run.font.size = Pt(14)
    return p

def add_numbered(text, indent_cm=1.0):
    p = doc.add_paragraph(style="List Number")
    p.paragraph_format.left_indent  = Cm(indent_cm)
    p.paragraph_format.space_before = Pt(2)
    p.paragraph_format.space_after  = Pt(2)
    run = p.add_run(text)
    run.font.name = "TH Sarabun New"
    run.font.size = Pt(14)
    return p

def add_code(text):
    p = doc.add_paragraph()
    p.paragraph_format.left_indent  = Cm(1)
    p.paragraph_format.space_before = Pt(4)
    p.paragraph_format.space_after  = Pt(4)
    shading = OxmlElement("w:shd")
    shading.set(qn("w:val"), "clear")
    shading.set(qn("w:color"), "auto")
    shading.set(qn("w:fill"), "F2F2F2")
    p._p.get_or_add_pPr().append(shading)
    run = p.add_run(text)
    run.font.name = "Courier New"
    run.font.size = Pt(11)
    return p

def add_image_placeholder(label):
    """กรอบ placeholder แทนรูปจริง"""
    img_path = os.path.join(IMAGES_DIR, label.split("(")[0].strip().split()[-1])
    # ถ้ามีรูปจริงในโฟลเดอร์ images/ ให้ใส่รูปจริง
    for ext in ("", ".png", ".jpg", ".jpeg"):
        candidate = img_path + ext if not img_path.endswith((".png",".jpg",".jpeg")) else img_path
        if os.path.isfile(candidate):
            p = doc.add_paragraph()
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            run = p.add_run()
            run.add_picture(candidate, width=Inches(5.5))
            cap = doc.add_paragraph(label)
            cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
            run2 = cap.runs[0] if cap.runs else cap.add_run(label)
            run2.font.name = "TH Sarabun New"
            run2.font.size = Pt(11)
            run2.italic = True
            return

    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(6)
    p.paragraph_format.space_after  = Pt(6)
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    shading = OxmlElement("w:shd")
    shading.set(qn("w:val"), "clear")
    shading.set(qn("w:color"), "auto")
    shading.set(qn("w:fill"), "E9EFF7")
    p._p.get_or_add_pPr().append(shading)
    run = p.add_run(f"[ รูปภาพ: {label} ]")
    run.font.name = "TH Sarabun New"
    run.font.size = Pt(12)
    run.italic = True
    run.font.color.rgb = RGBColor(0x44, 0x72, 0xC4)

def add_table(headers, rows):
    table = doc.add_table(rows=1+len(rows), cols=len(headers))
    table.style = "Table Grid"
    table.alignment = WD_TABLE_ALIGNMENT.LEFT
    hrow = table.rows[0]
    for i, h in enumerate(headers):
        cell = hrow.cells[i]
        cell.text = h
        cell.paragraphs[0].runs[0].bold = True
        cell.paragraphs[0].runs[0].font.name = "TH Sarabun New"
        cell.paragraphs[0].runs[0].font.size = Pt(13)
        tc = cell._tc
        tcPr = tc.get_or_add_tcPr()
        shd = OxmlElement("w:shd")
        shd.set(qn("w:val"), "clear")
        shd.set(qn("w:color"), "auto")
        shd.set(qn("w:fill"), "2E74B5")
        tcPr.append(shd)
        cell.paragraphs[0].runs[0].font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
    for r, row in enumerate(rows):
        trow = table.rows[r+1]
        fill = "F2F2F2" if r % 2 == 0 else "FFFFFF"
        for c, val in enumerate(row):
            cell = trow.cells[c]
            cell.text = val
            cell.paragraphs[0].runs[0].font.name = "TH Sarabun New"
            cell.paragraphs[0].runs[0].font.size = Pt(13)
            tc = cell._tc
            tcPr = tc.get_or_add_tcPr()
            shd = OxmlElement("w:shd")
            shd.set(qn("w:val"), "clear")
            shd.set(qn("w:color"), "auto")
            shd.set(qn("w:fill"), fill)
            tcPr.append(shd)
    doc.add_paragraph()

def add_note(text):
    p = doc.add_paragraph()
    p.paragraph_format.left_indent  = Cm(1)
    p.paragraph_format.space_before = Pt(4)
    p.paragraph_format.space_after  = Pt(4)
    shading = OxmlElement("w:shd")
    shading.set(qn("w:val"), "clear")
    shading.set(qn("w:color"), "auto")
    shading.set(qn("w:fill"), "FFF8DC")
    p._p.get_or_add_pPr().append(shading)
    run = p.add_run(f"📌 หมายเหตุ: {text}")
    run.font.name = "TH Sarabun New"
    run.font.size = Pt(13)
    run.italic = True

# ══════════════════════════════════════════════════════════════════════════════
# Title page
# ══════════════════════════════════════════════════════════════════════════════
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
p.paragraph_format.space_before = Pt(60)
run = p.add_run("คู่มือการติดตั้ง MyARAP")
run.font.name  = "TH Sarabun New"
run.font.size  = Pt(36)
run.bold       = True
run.font.color.rgb = RGBColor(0x1F, 0x49, 0x7D)

for label, value in [("เวอร์ชัน", "1.0.0"), ("ผู้พัฒนา", "ARSoft Mobile")]:
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(8)
    run = p.add_run(f"{label}: {value}")
    run.font.name = "TH Sarabun New"
    run.font.size = Pt(16)

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# 1. ความต้องการของระบบ
# ══════════════════════════════════════════════════════════════════════════════
add_heading("1. ความต้องการของระบบ", 1)
add_table(
    ["รายการ", "Windows", "macOS"],
    [
        ["ระบบปฏิบัติการ", "Windows 10 (64-bit) ขึ้นไป", "macOS 10.15 Catalina ขึ้นไป"],
        ["สถาปัตยกรรม", "x64", "Intel / Apple Silicon (M1 ขึ้นไป)"],
        ["RAM", "4 GB ขึ้นไป", "4 GB ขึ้นไป"],
        ["พื้นที่ดิสก์", "200 MB", "200 MB"],
        ["เครือข่าย", "เครือข่ายภายในองค์กร", "เครือข่ายภายในองค์กร"],
    ]
)

# ══════════════════════════════════════════════════════════════════════════════
# 2. การติดตั้งบน Windows
# ══════════════════════════════════════════════════════════════════════════════
add_heading("2. การติดตั้งบน Windows", 1)

add_heading("ขั้นตอนที่ 1 — ดาวน์โหลดไฟล์ติดตั้ง", 2)
add_para("ดาวน์โหลดไฟล์ติดตั้งจากแผนก IT โดยมีให้เลือก 2 รูปแบบ")
add_table(
    ["รูปแบบ", "ไฟล์", "เหมาะสำหรับ"],
    [
        ["EXE (แนะนำ)", "MyARAP_Setup.exe", "ติดตั้งทั่วไป มี Wizard แนะนำ"],
        ["MSI", "MyARAP.msi", "ติดตั้งผ่าน Group Policy / Silent install"],
    ]
)

add_heading("ขั้นตอนที่ 2 — อนุญาตแอปพลิเคชัน (Windows SmartScreen)", 2)
add_para("เนื่องจาก MyARAP เป็นซอฟต์แวร์ภายในองค์กรที่ไม่ได้ผ่าน Microsoft Store "
         "Windows อาจแสดงคำเตือนจาก SmartScreen")

add_para("1. คลิก \"More info\" (ข้อมูลเพิ่มเติม)", bold=True)
add_image_placeholder("Windows SmartScreen — หน้าต่างคำเตือน win_smartscreen_1.png")

add_para("2. คลิกปุ่ม \"Run anyway\" (เรียกใช้งานต่อไป)", bold=True)
add_image_placeholder("Windows SmartScreen — ปุ่ม Run anyway win_smartscreen_2.png")

add_note("หากไม่พบปุ่ม \"Run anyway\" ให้คลิกขวาที่ไฟล์ → Properties → แท็บ General "
         "→ ติ๊กถูก Unblock → OK แล้วเปิดไฟล์อีกครั้ง")
add_image_placeholder("File Properties — ช่อง Unblock win_properties_unblock.png")

add_heading("ขั้นตอนที่ 3 — ติดตั้งโปรแกรม (EXE)", 2)
add_numbered("ดับเบิลคลิกไฟล์ MyARAP_Setup.exe")
add_numbered("หากมีหน้าต่าง User Account Control (UAC) ปรากฏขึ้น คลิก Yes")
add_image_placeholder("User Account Control — คลิก Yes win_uac.png")
add_numbered("หน้าต่าง Setup Wizard จะเปิดขึ้น คลิก Next")
add_image_placeholder("Setup Wizard — หน้า Welcome win_installer_welcome.png")
add_numbered("อ่านและยอมรับ License Agreement แล้วคลิก Next")
add_numbered("เลือกโฟลเดอร์ติดตั้ง (ค่าเริ่มต้น: C:\\Program Files\\MyARAP) แล้วคลิก Next")
add_numbered("เลือกว่าต้องการสร้าง Desktop shortcut หรือไม่ แล้วคลิก Next")
add_numbered("คลิก Install เพื่อเริ่มติดตั้ง")
add_numbered("เมื่อติดตั้งเสร็จ คลิก Finish")
add_image_placeholder("Setup Wizard — หน้า Installation Complete win_installer_finish.png")

add_heading("ขั้นตอนที่ 3 — ติดตั้งโปรแกรม (MSI)", 2)
add_para("ดับเบิลคลิกไฟล์ MyARAP.msi แล้วทำตาม Wizard หรือติดตั้งแบบ Silent ผ่าน Command Prompt (Admin):")
add_code("msiexec /i MyARAP.msi /quiet /norestart")

add_heading("การใช้งาน System Tray", 2)
add_para("MyARAP รองรับการย่อลง System Tray แทนการปิดโปรแกรม")
add_image_placeholder("ไอคอน MyARAP ใน System Tray มุมขวาล่างของหน้าจอ win_tray_icon.png")
add_bullet("กดปุ่ม Minimize (−): โปรแกรมจะซ่อนลง System Tray")
add_bullet("คลิกซ้ายที่ไอคอน Tray: เปิดหน้าต่างโปรแกรมขึ้นมา")
add_bullet("คลิกขวาที่ไอคอน Tray: แสดงเมนู Open / Exit")
add_image_placeholder("เมนูคลิกขวา Tray — Open และ Exit win_tray_menu.png")

# ══════════════════════════════════════════════════════════════════════════════
# 3. การติดตั้งบน macOS
# ══════════════════════════════════════════════════════════════════════════════
add_heading("3. การติดตั้งบน macOS", 1)

add_heading("ขั้นตอนที่ 1 — ดาวน์โหลดไฟล์ติดตั้ง", 2)
add_para("ดาวน์โหลดไฟล์ MyARAP.dmg จากแผนก IT")

add_heading("ขั้นตอนที่ 2 — อนุญาตแอปพลิเคชันที่ไม่ได้มาจาก App Store", 2)
add_para("เนื่องจาก MyARAP เป็นซอฟต์แวร์ภายในองค์กรที่ไม่ได้ผ่าน Mac App Store "
         "macOS จะบล็อกการเปิดโปรแกรมโดยค่าเริ่มต้น")

add_heading("วิธีที่ 1 — เปิดครั้งแรกผ่านเมนูคลิกขวา (แนะนำ)", 3)
add_numbered("เปิดไฟล์ MyARAP.dmg และลาก MyARAP.app ไปวางใน Applications")
add_numbered("เปิดโฟลเดอร์ Applications ใน Finder")
add_numbered("คลิกขวา (หรือ Control+คลิก) ที่ MyARAP.app → เลือก Open")
add_image_placeholder("Finder — คลิกขวาที่ MyARAP.app แล้วเลือก Open mac_rightclick_open.png")
add_numbered('กล่องข้อความจะถามว่า "macOS cannot verify the developer" ให้คลิก Open')
add_image_placeholder("Dialog ยืนยัน — คลิก Open mac_open_confirm.png")
add_note("หลังจากทำครั้งแรกแล้ว ครั้งต่อไปสามารถเปิดโปรแกรมได้ตามปกติ")

add_heading("วิธีที่ 2 — เปิดอนุญาตผ่าน System Settings", 3)
add_para('หากเปิดโปรแกรมแล้วเห็นข้อความ "MyARAP cannot be opened because it is from an unidentified developer"')
add_image_placeholder("Dialog — MyARAP cannot be opened mac_blocked_dialog.png")

add_para("macOS Ventura (13) ขึ้นไป:", bold=True)
add_numbered("เปิด System Settings → Privacy & Security")
add_image_placeholder("System Settings — หน้า Privacy & Security mac_system_settings.png")
add_numbered("เลื่อนลงไปที่หัวข้อ Security → คลิกปุ่ม Open Anyway")
add_image_placeholder("ปุ่ม Open Anyway ในหน้า Privacy & Security mac_open_anyway.png")
add_numbered("กรอกรหัสผ่าน Mac แล้วคลิก OK")

add_para("macOS Monterey (12) หรือเก่ากว่า:", bold=True)
add_numbered("เปิด System Preferences → Security & Privacy → แท็บ General")
add_numbered("คลิก 🔒 แล้วกรอกรหัสผ่านเพื่อปลดล็อก")
add_numbered("คลิก Open Anyway ที่อยู่ใต้ข้อความเตือน")

add_heading("วิธีที่ 3 — ใช้ Terminal (กรณีที่ปุ่มไม่ปรากฏ)", 3)
add_para("เปิด Terminal แล้วรันคำสั่ง:")
add_code("xattr -cr /Applications/MyARAP.app")
add_para("จากนั้นเปิดโปรแกรมได้ตามปกติ")

add_heading("ขั้นตอนที่ 3 — ติดตั้งโปรแกรม", 2)
add_numbered("เปิดไฟล์ MyARAP.dmg โดยดับเบิลคลิก")
add_numbered("ลาก MyARAP.app ไปวางบนไอคอน Applications")
add_image_placeholder("หน้าต่าง DMG — ลาก MyARAP.app ไปวาง Applications mac_dmg_window.png")
add_numbered("รอจนคัดลอกเสร็จ แล้วปิดหน้าต่าง DMG")
add_numbered("นำ DMG ออกจากระบบ: คลิกขวา DMG ใน Finder → Eject")
add_numbered("เปิดโปรแกรมจาก Applications หรือ Launchpad")

# ══════════════════════════════════════════════════════════════════════════════
# 4. การตั้งค่าครั้งแรก
# ══════════════════════════════════════════════════════════════════════════════
add_heading("4. การตั้งค่าครั้งแรก", 1)
add_para("เมื่อเปิดโปรแกรมครั้งแรก MyARAP จะทำการตรวจสอบตัวตนโดยอัตโนมัติจากข้อมูลฮาร์ดแวร์ของเครื่อง "
         "ไม่ต้องกรอก Username / Password", bold=False)
add_para("หากต้องการเปลี่ยน Server URL (กรณีแผนก IT แจ้งที่อยู่เซิร์ฟเวอร์ใหม่):", bold=True)
add_numbered("คลิกเมนู Settings (การตั้งค่า)")
add_numbered("แก้ไข Server URL ให้ตรงกับที่แผนก IT กำหนด")
add_numbered("คลิก Save แล้วรีสตาร์ทโปรแกรม")

# ══════════════════════════════════════════════════════════════════════════════
# 5. การถอนการติดตั้ง
# ══════════════════════════════════════════════════════════════════════════════
add_heading("5. การถอนการติดตั้ง", 1)

add_heading("Windows", 2)
add_para("วิธีที่ 1 — ผ่าน Control Panel:", bold=True)
add_numbered("เปิด Control Panel → Programs → Uninstall a program")
add_numbered("เลือก MyARAP แล้วคลิก Uninstall")

add_para("วิธีที่ 2 — ผ่าน Start Menu:", bold=True)
add_numbered("เปิด Start Menu → MyARAP")
add_numbered("คลิก Uninstall MyARAP")

add_heading("macOS", 2)
add_numbered("เปิด Finder → Applications")
add_numbered("ลาก MyARAP.app ไปวางในถังขยะ")
add_numbered("กด Command + Delete เพื่อล้างถังขยะ")

# ══════════════════════════════════════════════════════════════════════════════
# 6. ติดต่อฝ่าย IT
# ══════════════════════════════════════════════════════════════════════════════
add_heading("6. ติดต่อฝ่าย IT", 1)
add_para("หากพบปัญหาในการติดตั้งหรือใช้งาน กรุณาติดต่อแผนก IT ภายในองค์กร")

# ── Save ──────────────────────────────────────────────────────────────────────
doc.save(OUT_PATH)
print(f"บันทึกสำเร็จ: {OUT_PATH}")
