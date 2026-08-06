import 'package:flutter/material.dart';

import '../../core/config/app_colors.dart';

/// สี + ป้ายภาษาไทยของสถานะ/ความเร่งด่วน ticket — **จุดเดียวของทั้งแอป**
///
/// เดิมตารางเดียวกันนี้ถูกก็อปไว้ 3 ที่ (`problem_screen` · `problem_detail_screen` ×2)
/// และเริ่มไม่ตรงกันแล้ว — `assigned` เป็นส้มที่หนึ่ง แต่อีกที่แมปเป็นสีเทา
///
/// สีมาจาก `AppPalette` (ok/warn/crit/cyan) ไม่ใช่ `Colors.red` ตรง ๆ เพื่อให้อ่านออก
/// ทั้งโหมดสว่างและมืด — แดงของ Material บนพื้นเข้มจมหายไปกับพื้นหลัง
class TicketStyle {
  TicketStyle._();

  static String statusLabel(String s) => switch (s) {
        'new' || 'Open' || 'Opened' => 'รอดำเนินการ',
        'assigned' => 'มอบหมายแล้ว',
        'in_progress' || 'In Progress' || 'Processing' => 'กำลังดำเนินการ',
        'resolved' || 'Resolved' => 'แก้ไขแล้ว',
        'closed' || 'Closed' => 'ปิดแล้ว',
        'cancelled' => 'ยกเลิก',
        _ => s,
      };

  static Color statusColor(AppPalette c, String s) => switch (s) {
        'new' || 'Open' || 'Opened' => c.crit,
        'assigned' => c.warn,
        'in_progress' || 'In Progress' || 'Processing' => c.cyan,
        // "แก้ไขแล้ว" ใช้สีเตือน ไม่ใช่สีเขียว — เพราะยังไม่จบ ผู้ใช้ต้องเข้ามายืนยันปิดงาน
        'resolved' || 'Resolved' => c.warn,
        'closed' || 'Closed' => c.ok,
        'cancelled' => c.dim,
        _ => c.dim,
      };

  static String priorityLabel(String p) => switch (p) {
        'critical' => 'วิกฤต',
        'high' => 'สูง',
        'medium' => 'ปานกลาง',
        'low' => 'ต่ำ',
        _ => p,
      };

  static Color priorityColor(AppPalette c, String p) => switch (p) {
        'critical' => c.crit,
        'high' => c.warn,
        'medium' => c.cyan,
        'low' => c.dim,
        _ => c.dim,
      };

  /// สถานะที่ "จบแล้ว" — ซ่อนช่องเพิ่มบันทึก/ปุ่มปิดงาน
  static bool isFinal(String s) =>
      const ['closed', 'Closed', 'cancelled'].contains(s);

  /// รอผู้ใช้ยืนยันปิดงาน — ตัวเลขในการ์ด "ต้องทำ" ของหน้าแรกและ badge เมนูซ้าย
  static bool needsUserAction(String s) =>
      s == 'resolved' || s == 'Resolved';
}

/// ช่องกรอกข้อความมาตรฐานของ agent — ใช้สีจาก palette แทน `Colors.grey.shade300`
/// ที่มองไม่เห็นบนพื้นเข้ม
InputDecoration appInput(AppPalette c, String hint) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 12.5, color: c.dim),
      filled: true,
      fillColor: c.isDark ? c.bg : c.soft,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: c.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: c.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: c.violet.withValues(alpha: 0.7)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
    );

/// ปุ่มหลัก (ไล่สีแบรนด์) — ปุ่มเดียวต่อหน้าจอ: ส่งเรื่อง / ยืนยันปิดงาน
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final btn = DecoratedBox(
      decoration: BoxDecoration(
        gradient: enabled ? AppColors.brandGradient : null,
        color: enabled ? null : AppColors.of(context).soft,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: enabled ? onPressed : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                else if (icon != null)
                  Icon(icon, size: 15, color: enabled ? Colors.white : AppColors.of(context).dim),
                if (busy || icon != null) const SizedBox(width: 8),
                Text(label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: enabled ? Colors.white : AppColors.of(context).dim,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// ปุ่มรอง — ขอบบาง ๆ ไม่แย่งสายตากับปุ่มหลัก
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final fg = onPressed == null ? c.dim : (color ?? c.ink);
    final btn = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: (color ?? c.line).withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 7),
              ],
              Text(label,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500, color: fg)),
            ],
          ),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// ความกว้างของคอลัมน์รายการในหน้าที่แบ่งซ้าย–ขวา
///
/// **อย่า fix เป็นค่าคงที่** — หน้าต่างจริงเปิดที่ 1280 ก็จริง แต่ผู้ใช้ย่อได้ และเคยเจอมาแล้วว่า
/// ที่ 800px แผงขวาเหลือ 180px จนปุ่มล้นออกนอกกรอบ. ให้รายการกินสัดส่วนแทน
/// เพื่อให้แผงรายละเอียด (ของที่ผู้ใช้มาอ่านจริง ๆ) ได้พื้นที่เป็นสัดส่วนเสมอ
double listPaneWidth(double available) =>
    (available * 0.34).clamp(240.0, 340.0);

/// สถานะว่าง — ไอคอนจาง + ข้อความ ใช้ทุก section ให้หน้าตาเหมือนกัน
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text, this.hint});
  final IconData icon;
  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: c.dim.withValues(alpha: 0.45)),
          const SizedBox(height: 10),
          Text(text, style: TextStyle(fontSize: 13, color: c.dim)),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: c.dim.withValues(alpha: 0.75))),
          ],
        ],
      ),
    );
  }
}
