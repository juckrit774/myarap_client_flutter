import 'package:flutter/material.dart';

import '../../../../core/config/app_colors.dart';
import '../../../../core/services/network_manager.dart';
import '../../../../shared/widgets/ticket_style.dart';

/// แบบสำรวจความพึงพอใจหลังปิดเรื่อง — เด้งครั้งเดียวจบ ตอบหรือข้ามก็ได้
///
/// เป็น **ชั้นที่ 2 จริง ๆ** (โผล่มาแล้วหายไป ไม่ใช่หน้าที่สลับไปมา) จึงใช้ dialog ได้
/// ตามกติกาของ AppShell
void showCsatDialog(
  BuildContext context, {
  required String token,
  required String ticketNumber,
  required String ticketTitle,
}) {
  showDialog(
    context: context,
    builder: (_) => _CsatDialog(
      token: token,
      ticketNumber: ticketNumber,
      ticketTitle: ticketTitle,
    ),
  );
}

class _CsatDialog extends StatefulWidget {
  const _CsatDialog({
    required this.token,
    required this.ticketNumber,
    required this.ticketTitle,
  });
  final String token, ticketNumber, ticketTitle;

  @override
  State<_CsatDialog> createState() => _CsatDialogState();
}

class _CsatDialogState extends State<_CsatDialog> {
  int _score = 0;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;
  bool _done = false;
  String? _err;

  static const _labels = ['แย่มาก', 'แย่', 'พอใช้', 'ดี', 'ดีมาก'];

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  /// สีดาว: 1–2 = วิกฤต · 3 = ต้องระวัง · 4–5 = ปกติ (ใช้ palette เดียวกับสถานะ
  /// ไม่ใช่ Colors.red/amber/green ตรง ๆ ที่อ่านไม่ออกบนพื้นเข้ม)
  Color _scoreColor(AppPalette c, int score) =>
      score <= 2 ? c.crit : (score == 3 ? c.warn : c.ok);

  Future<void> _submit() async {
    if (_score == 0) {
      setState(() => _err = 'เลือกจำนวนดาวก่อนส่ง');
      return;
    }
    setState(() {
      _submitting = true;
      _err = null;
    });
    try {
      await NetworkManager.instance.postV3Public('/api/v1/csat/survey', {
        'token': widget.token,
        'score': _score,
        'comment': _commentCtrl.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        _done = true;
        _submitting = false;
      });
      await Future.delayed(const Duration(milliseconds: 1800));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = e.toString();
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Dialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: c.line),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: _done ? _thanks(c) : _form(c),
        ),
      ),
    );
  }

  Widget _thanks(AppPalette c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 44, color: c.ok),
          const SizedBox(height: 11),
          Text('ขอบคุณสำหรับความคิดเห็น',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
        ],
      );

  Widget _form(AppPalette c) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('ช่างแก้ปัญหาให้เป็นอย่างไรบ้าง',
                  style: TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w600, color: c.ink)),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 18, color: c.dim),
              onPressed: () => Navigator.of(context).pop(),
              splashRadius: 16,
            ),
          ]),
          Text(
            '${widget.ticketNumber}${widget.ticketTitle.isEmpty ? '' : ' — ${widget.ticketTitle}'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: c.dim),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final on = i < _score;
              return IconButton(
                onPressed: () => setState(() => _score = i + 1),
                splashRadius: 22,
                icon: Icon(
                  on ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 34,
                  color: on ? _scoreColor(c, _score) : c.dim.withValues(alpha: 0.5),
                ),
              );
            }),
          ),
          if (_score > 0)
            Center(
              child: Text(_labels[_score - 1],
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _scoreColor(c, _score))),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _commentCtrl,
            minLines: 2,
            maxLines: 4,
            style: TextStyle(fontSize: 12.5, color: c.ink),
            decoration: appInput(c, 'อยากบอกอะไรเพิ่มเติม (ไม่บังคับ)'),
          ),
          if (_err != null) ...[
            const SizedBox(height: 6),
            Text(_err!, style: TextStyle(fontSize: 11, color: c.crit)),
          ],
          const SizedBox(height: 16),
          Row(children: [
            PrimaryButton(
              label: 'ส่งคะแนน',
              busy: _submitting,
              onPressed: _submitting ? null : _submit,
            ),
            const SizedBox(width: 8),
            GhostButton(
              label: 'ข้ามไปก่อน',
              onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            ),
          ]),
        ],
      );
}
