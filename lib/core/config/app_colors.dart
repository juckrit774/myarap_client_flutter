import 'package:flutter/material.dart';

/// ชุดสีของ agent — **ใช้ชุดเดียวกับเว็บ MYARAP** (`frontend/src/theme.ts`)
///
/// เดิมเป็นม่วง `#42286F`/`#745895` + ส้ม `#FBAC53` ซึ่งเป็นคนละชุดกับเว็บ
/// ทำให้ agent กับเว็บดูเหมือนคนละผลิตภัณฑ์ทั้งที่เป็นระบบเดียวกัน
///
/// **วิธีใช้ในโค้ดใหม่**: `final c = AppColors.of(context);` แล้วใช้ `c.ink` / `c.card` / …
/// จะได้สลับสว่าง–มืดตามระบบเองโดยไม่ต้องเขียนเงื่อนไข
///
/// ⚠️ ค่าคงที่ท้ายไฟล์ (`mainPurple` / `bgColor` / …) เป็น **alias ของเดิม** ที่ชี้มาสีใหม่
/// มีไว้ให้หน้าที่ยังไม่ได้เขียนใหม่คอมไพล์ผ่านและได้สีแบรนด์ใหม่ไปด้วย —
/// **อย่าใช้ในโค้ดใหม่** และทยอยลบออกเมื่อย้ายครบทุกหน้าแล้ว
class AppColors {
  AppColors._();

  // ── accent (เหมือนกันทั้งสองโหมด) ─────────────────────────────────────────
  /// ไล่สีหลักของแบรนด์ — ปุ่มหลัก โลโก้ แถบ progress (ตรงกับ `--grad` ฝั่งเว็บ)
  static const violet = Color(0xFF6F63E6);
  static const cyan = Color(0xFF3FB6C9);
  static const brandGradient = LinearGradient(
    colors: [violet, cyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const _lBg = Color(0xFFF6F7FB);
  static const _lCard = Color(0xFFFFFFFF);
  static const _lInk = Color(0xFF141A26);
  static const _lDim = Color(0xFF68738A);
  static const _lLine = Color(0xFFE3E8F1);
  static const _lSoft = Color(0xFFEEF1F6);
  static const _lOk = Color(0xFF0F9D6A);
  static const _lWarn = Color(0xFFB06F04);
  static const _lCrit = Color(0xFFD13A5C);

  static const _dBg = Color(0xFF0D1119);
  static const _dCard = Color(0xFF151C2A);
  static const _dInk = Color(0xFFE6EBF6);
  static const _dDim = Color(0xFF8B95AB);
  static const _dLine = Color(0xFF26303F);
  static const _dSoft = Color(0xFF1B2331);
  static const _dOk = Color(0xFF34D399);
  static const _dWarn = Color(0xFFFFB84D);
  static const _dCrit = Color(0xFFFF5B7F);
  static const _dViolet = Color(0xFF8B80F0);

  static const light = AppPalette(
    bg: _lBg, card: _lCard, ink: _lInk, dim: _lDim, line: _lLine, soft: _lSoft,
    violet: violet, cyan: cyan, ok: _lOk, warn: _lWarn, crit: _lCrit,
    isDark: false,
  );
  static const dark = AppPalette(
    bg: _dBg, card: _dCard, ink: _dInk, dim: _dDim, line: _dLine, soft: _dSoft,
    violet: _dViolet, cyan: cyan, ok: _dOk, warn: _dWarn, crit: _dCrit,
    isDark: true,
  );

  static AppPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  // ── alias ของเดิม (deprecated) ────────────────────────────────────────────
  @Deprecated('ใช้ AppColors.of(context).violet แทน')
  static const deepPurple = violet;
  @Deprecated('ใช้ AppColors.of(context).violet แทน')
  static const mainPurple = violet;
  @Deprecated('ใช้ AppColors.of(context).cyan แทน')
  static const opaPurple = cyan;
  @Deprecated('ใช้ AppColors.of(context).bg แทน')
  static const bgColor = _lBg;
  @Deprecated('ใช้ AppColors.of(context).warn แทน')
  static const orange = _lWarn;
  @Deprecated('ใช้ AppColors.brandGradient แทน')
  static const headerGradient = brandGradient;
}

/// ชุดสีที่ resolve ตามโหมดแล้ว — ชื่อ field ตรงกับ CSS var ฝั่งเว็บ
/// (`--bg` `--card` `--ink` `--dim` `--line` `--soft`) เพื่อให้เทียบข้ามฝั่งได้ง่าย
@immutable
class AppPalette {
  final Color bg;
  final Color card;

  /// สีตัวอักษรหลัก
  final Color ink;

  /// สีตัวอักษรรอง / label
  final Color dim;
  final Color line;

  /// พื้นอ่อนสำหรับ chip / รายการเมนูที่ถูกเลือก
  final Color soft;
  final Color violet;
  final Color cyan;

  /// สีตามความหมาย — **แยกจาก accent โดยเจตนา** (ปกติ / ต้องระวัง / วิกฤต)
  /// ห้ามเอา violet/cyan มาสื่อความหมายสถานะ ไม่งั้นเปลี่ยนธีมแล้วความหมายเพี้ยน
  final Color ok;
  final Color warn;
  final Color crit;
  final bool isDark;

  const AppPalette({
    required this.bg,
    required this.card,
    required this.ink,
    required this.dim,
    required this.line,
    required this.soft,
    required this.violet,
    required this.cyan,
    required this.ok,
    required this.warn,
    required this.crit,
    required this.isDark,
  });

  /// พื้นหลังจาง ๆ ของสีตามความหมาย — ใช้กับ chip/การ์ดที่ต้องเน้น
  /// โหมดมืดใช้ alpha สูงกว่าเล็กน้อยเพราะพื้นดำกลืนสีจางไปหมด
  Color tint(Color c) => c.withValues(alpha: isDark ? 0.18 : 0.12);
}
