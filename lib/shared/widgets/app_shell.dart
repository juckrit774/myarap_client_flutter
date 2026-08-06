import 'package:flutter/material.dart';

import '../../core/config/app_colors.dart';
import '../../core/config/app_config.dart';

/// หน้าจอที่เลือกได้จากเมนูซ้าย
enum AppSection { device, report, tickets, notifications, settings }

/// คำขอเปลี่ยนหน้าจาก**นอก widget tree** — เมนู Settings ของ macOS / tray ยิงเข้ามาที่
/// `main.dart` ซึ่งไม่มี context ของ shell. เดิม main.dart แก้ด้วย `Navigator.push`
/// หน้า Settings ซ้อนขึ้นมา (เมนูซ้ายหาย ต้องกด Back) — ผิดกติกาข้อเดียวของแบบ A
///
/// HomeScreen รับค่าไปสลับ section แล้ว **รีเซ็ตกลับเป็น null** เพื่อให้สั่งซ้ำค่าเดิมได้
/// (ValueNotifier ไม่ยิง listener ถ้าค่าไม่เปลี่ยน — กดเมนูเดิมสองครั้งจะเงียบ)
final requestedSection = ValueNotifier<AppSection?>(null);

/// AppShell = โครงหลักของ agent แบบ **A · คอนโซล** — เมนูซ้ายคงที่ + พื้นที่เนื้อหาขวา
///
/// ทำไมถึงเปลี่ยนจากของเดิม: หน้าต่าง agent เปิดที่ **1280×720** แต่ UI เดิมวางแบบแอปมือถือ
/// (คอลัมน์เดียว + app bar + `Navigator.push` ซ้อนกันไปเรื่อย ๆ) พื้นที่แนวนอนกว่าครึ่งจอ
/// ถูกทิ้งว่าง และผู้ใช้ต้องกด Back ย้อนทีละชั้นเพื่อสลับหน้า
///
/// ⚠️ **ห้ามใช้ `Navigator.push` สลับหน้าหลักอีก** — เปลี่ยน section ผ่าน [onSelect]
/// เพื่อให้เมนูซ้ายและ badge การแจ้งเตือนอยู่ในสายตาตลอดเวลา
/// (Navigator ยังใช้ได้กับ dialog / รูปแนบ / หน้าต่างย่อย ซึ่งเป็นชั้นที่ 2 จริง ๆ)
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.current,
    required this.onSelect,
    required this.child,
    this.userName = '',
    this.userAccount = '',
    this.roleLabel = '',
    this.ticketBadge = 0,
    this.notifBadge = 0,
  });

  final AppSection current;
  final ValueChanged<AppSection> onSelect;
  final Widget child;
  final String userName;
  final String userAccount;

  /// สิทธิ์ในระบบ MYARAP (End-user / Technician / IT-Asset Manager / Admin)
  /// แสดงเพื่อให้ผู้ใช้กับช่างพูดถึงสิ่งเดียวกันตอนโทรคุยกัน —
  /// **ไม่ได้เปลี่ยนสิ่งที่ทำได้ในตัว agent** งานจัดการทั้งหมดอยู่บนเว็บ
  final String roleLabel;
  final int ticketBadge;
  final int notifBadge;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Rail(
            current: current,
            onSelect: onSelect,
            userName: userName,
            userAccount: userAccount,
            roleLabel: roleLabel,
            ticketBadge: ticketBadge,
            notifBadge: notifBadge,
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.current,
    required this.onSelect,
    required this.userName,
    required this.userAccount,
    required this.roleLabel,
    required this.ticketBadge,
    required this.notifBadge,
  });

  final AppSection current;
  final ValueChanged<AppSection> onSelect;
  final String userName, userAccount, roleLabel;
  final int ticketBadge, notifBadge;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      width: 206,
      decoration: BoxDecoration(
        color: c.card,
        border: Border(right: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _brand(c),
          const SizedBox(height: 4),
          _item(context, AppSection.device, Icons.computer_outlined, 'เครื่องของฉัน'),
          _item(context, AppSection.report, Icons.edit_outlined, 'แจ้งปัญหา'),
          _item(context, AppSection.tickets, Icons.list_alt_outlined, 'ปัญหาที่แจ้ง',
              badge: ticketBadge),
          _item(context, AppSection.notifications, Icons.notifications_none, 'การแจ้งเตือน',
              badge: notifBadge),
          _item(context, AppSection.settings, Icons.settings_outlined, 'ตั้งค่า'),
          const Spacer(),
          _user(c),
        ],
      ),
    );
  }

  Widget _brand(AppPalette c) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 14),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: const Text('M',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('MYARAP',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.4,
                          color: c.ink)),
                  Text('Agent ${AppConfig.appVersion}',
                      style: TextStyle(fontSize: 10, color: c.dim)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _item(BuildContext context, AppSection s, IconData icon, String label,
      {int badge = 0}) {
    final c = AppColors.of(context);
    final on = s == current;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: on ? c.violet.withValues(alpha: c.isDark ? 0.18 : 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () => onSelect(s),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(icon, size: 17, color: on ? c.violet : c.dim),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: on ? c.violet : c.dim,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                      )),
                ),
                if (badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                        color: c.crit, borderRadius: BorderRadius.circular(99)),
                    child: Text('$badge',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _user(AppPalette c) {
    if (userName.isEmpty) return const SizedBox.shrink();
    final initial = userName.trim().isNotEmpty ? userName.trim()[0] : '?';
    return Container(
      padding: const EdgeInsets.only(top: 11, left: 6, right: 6),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(
                gradient: AppColors.brandGradient, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(initial,
                style: const TextStyle(
                    color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500, color: c.ink)),
                if (userAccount.isNotEmpty)
                  Text(userAccount,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: c.dim)),
                if (roleLabel.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: c.soft, borderRadius: BorderRadius.circular(99)),
                    child: Text(roleLabel,
                        style: TextStyle(
                            fontSize: 9.5, color: c.dim, fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// หัวข้อของแต่ละหน้า — ใช้ร่วมทุก section ให้ระยะขอบตรงกัน
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(title,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.ink)),
          if (subtitle != null) ...[
            const SizedBox(width: 11),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(subtitle!, style: TextStyle(fontSize: 11, color: c.dim)),
            ),
          ],
          // ⚠️ ห้ามใช้ `Spacer()` แล้ววาง trailing ต่อท้าย — trailing จะถูกวัดด้วย
          // ความกว้าง unbounded ทำให้ Row ที่ส่งเข้ามา (ปุ่มหลายตัว) ระเบิดตอน layout
          // จัดชิดขวาด้วย Expanded + MainAxisAlignment.end แทน ซึ่งให้ constraint ที่มีขอบเขต
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [?trailing],
            ),
          ),
        ],
      ),
    );
  }
}

/// การ์ดมาตรฐาน — ขอบ/มุม/พื้นเดียวกันทั้งแอป (`.c` ฝั่งเว็บ)
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(14, 13, 14, 13),
    this.accent,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;

  /// ใส่สีเพื่อเน้นการ์ด (ขอบ + พื้นจาง) — ใช้กับการ์ด "ต้องทำ" / "แก้ไขแล้ว"
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: accent == null ? c.card : accent!.withValues(alpha: c.isDark ? 0.10 : 0.06),
        border: Border.all(
            color: accent == null ? c.line : accent!.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(11),
      ),
      child: child,
    );
    if (onTap == null) return body;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: body,
    );
  }
}

/// หัวข้อเล็กในการ์ด — ตัวพิมพ์ใหญ่เว้นระยะ แบบเดียวกับ `.ctitle` ฝั่งเว็บ
class CardTitle extends StatelessWidget {
  const CardTitle(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text.toUpperCase(),
          style: TextStyle(
            fontSize: 9.5,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
            color: color ?? c.dim,
          )),
    );
  }
}

/// แถวคู่ key–value ในการ์ด
class KvRow extends StatelessWidget {
  const KvRow(this.label, this.value, {super.key, this.valueColor, this.mono = false});
  final String label, value;
  final Color? valueColor;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12.5, color: c.dim)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: valueColor ?? c.ink,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ป้ายสถานะ — สีมาจากความหมาย ไม่ใช่จาก accent
class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, required this.color, this.dot = true});
  final String text;
  final Color color;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
          color: c.tint(color), borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 5),
          ],
          Text(text,
              style: TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
