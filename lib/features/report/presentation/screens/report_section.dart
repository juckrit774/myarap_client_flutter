import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/config/app_colors.dart';
import '../../../../shared/widgets/app_shell.dart';
import '../../../../shared/widgets/ticket_style.dart';
import '../../../problem/models/m_problem_model.dart';
import '../view_models/report_view_model.dart';

/// หน้า "แจ้งปัญหา" — **ทุกอย่างอยู่ในหน้าเดียว**
///
/// ของเดิมต้องกดปุ่ม "เลือกปัญหา" เพื่อเปิด bottom sheet เต็มจอ (`SelectProblemScreen`)
/// เลือกเสร็จกด "เสร็จ" ปิด sheet แล้วค่อยกลับมาเห็นชิปที่เลือก — 3 คลิกก่อนจะเริ่มพิมพ์
/// ได้ ทั้งที่ทั้งรายการมีไม่ถึง 10 อัน และหน้าต่างกว้าง 1280 วางให้เห็นหมดได้ในทีเดียว
class ReportSection extends StatefulWidget {
  const ReportSection({super.key, this.onSent});

  /// ส่งเรื่องสำเร็จ → ให้ shell พาไปหน้า "ปัญหาที่แจ้ง" (เดิมแค่ pop กลับหน้าเดิม
  /// ผู้ใช้ไม่เห็นว่าเรื่องที่เพิ่งส่งไปอยู่ไหน)
  final VoidCallback? onSent;

  @override
  State<ReportSection> createState() => _ReportSectionState();
}

class _ReportSectionState extends State<ReportSection> {
  final _remarkCtrl = TextEditingController();

  @override
  void dispose() {
    _remarkCtrl.dispose();
    super.dispose();
  }

  Future<void> _send(ReportViewModel vm) async {
    final ok = await vm.sendReport(onError: _toast);
    if (!ok || !mounted) return;
    _remarkCtrl.clear();
    _toast('ส่งเรื่องแล้ว — ทีม IT จะติดต่อกลับ');
    widget.onSent?.call();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReportViewModel>();
    final c = AppColors.of(context);
    final needRemark = vm.selectedProblems.any((p) => p.requireRemark);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      children: [
        const SectionHeader(
          title: 'แจ้งปัญหา',
          subtitle: 'เลือกอาการที่พบ แล้วกดส่งเรื่อง',
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(children: [
                _problemCard(context, vm),
                const SizedBox(height: 11),
                _remarkCard(context, vm, needRemark),
              ]),
            ),
            const SizedBox(width: 11),
            Expanded(
              flex: 2,
              child: Column(children: [
                _imageCard(context, vm),
                const SizedBox(height: 11),
                _submitCard(context, vm, c, needRemark),
              ]),
            ),
          ],
        ),
      ],
    );
  }

  Widget _problemCard(BuildContext context, ReportViewModel vm) {
    final c = AppColors.of(context);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: CardTitle('อาการที่พบ')),
          if (vm.selectedProblems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('เลือกไว้ ${vm.selectedProblems.length}',
                  style: TextStyle(fontSize: 11, color: c.violet)),
            ),
        ]),
        if (vm.isLoading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: c.violet))),
          )
        else if (vm.problemTypes.isEmpty)
          Text('ยังโหลดรายการอาการไม่ได้ — พิมพ์อธิบายในช่องหมายเหตุแทนได้',
              style: TextStyle(fontSize: 12, color: c.dim))
        else
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final p in vm.problemTypes)
                _Chip(
                  problem: p,
                  onTap: () => vm.toggleProblem(p.id),
                ),
            ],
          ),
      ]),
    );
  }

  Widget _remarkCard(BuildContext context, ReportViewModel vm, bool needRemark) {
    final c = AppColors.of(context);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: CardTitle('รายละเอียดเพิ่มเติม')),
          if (needRemark)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('จำเป็นสำหรับอาการที่เลือก',
                  style: TextStyle(fontSize: 10.5, color: c.warn)),
            ),
        ]),
        TextField(
          controller: _remarkCtrl,
          minLines: 5,
          maxLines: 9,
          style: TextStyle(fontSize: 13, color: c.ink),
          decoration: appInput(c,
              'เกิดขึ้นตอนไหน ทำอะไรอยู่ เคยเป็นมาก่อนหรือไม่ — ยิ่งละเอียด ช่างยิ่งเตรียมของมาถูก'),
          onChanged: vm.setRemark,
        ),
      ]),
    );
  }

  Widget _imageCard(BuildContext context, ReportViewModel vm) {
    final c = AppColors.of(context);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CardTitle('รูปภาพประกอบ'),
        if (vm.images.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('แนบได้สูงสุด 3 รูป (ไฟล์ละไม่เกิน 2 MB)',
                style: TextStyle(fontSize: 11.5, color: c.dim)),
          )
        else ...[
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 7,
            mainAxisSpacing: 7,
            children: [
              for (final img in vm.images)
                Stack(fit: StackFit.expand, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(img.path), fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 3,
                    right: 3,
                    child: GestureDetector(
                      onTap: () => vm.removeImage(img.id),
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                            color: c.crit, shape: BoxShape.circle),
                        child: const Icon(Icons.close, color: Colors.white, size: 13),
                      ),
                    ),
                  ),
                ]),
            ],
          ),
          const SizedBox(height: 10),
          // เกิน 3 รูป view model จะตัดทิ้งเงียบ ๆ ตอนส่ง — บอกไว้ก่อนดีกว่าให้ผู้ใช้
          // เจอเองว่ารูปที่ 4 หายไปหลังส่งแล้ว
          if (vm.images.length > 3)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('จะส่งเฉพาะ 3 รูปแรก',
                  style: TextStyle(fontSize: 11, color: c.warn)),
            ),
        ],
        GhostButton(
          label: 'เลือกรูป',
          icon: Icons.image_outlined,
          expand: true,
          onPressed: vm.pickImage,
        ),
      ]),
    );
  }

  Widget _submitCard(
      BuildContext context, ReportViewModel vm, AppPalette c, bool needRemark) {
    final blocked = vm.validate();
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CardTitle('ส่งเรื่อง'),
        Text(
          blocked ?? 'เรื่องจะเข้าคิวของทีม IT ทันที และติดตามสถานะได้ที่เมนู “ปัญหาที่แจ้ง”',
          style: TextStyle(
              fontSize: 11.5, color: blocked == null ? c.dim : c.warn, height: 1.45),
        ),
        const SizedBox(height: 11),
        PrimaryButton(
          label: 'ส่งเรื่อง',
          icon: Icons.send,
          expand: true,
          busy: vm.isSending,
          onPressed: blocked != null || vm.isSending ? null : () => _send(vm),
        ),
      ]),
    );
  }
}

/// ชิปเลือกอาการ — แทน `SelectProblemScreen` (bottom sheet) ที่ลบทิ้งแล้ว
class _Chip extends StatelessWidget {
  const _Chip({required this.problem, required this.onTap});
  final MProblemModel problem;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final on = problem.isSelected;
    return Material(
      color: on ? c.violet.withValues(alpha: c.isDark ? 0.20 : 0.11) : c.soft,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
                color: on ? c.violet.withValues(alpha: 0.65) : Colors.transparent),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(on ? Icons.check_circle : Icons.add_circle_outline,
                size: 14, color: on ? c.violet : c.dim),
            const SizedBox(width: 7),
            Text(problem.name,
                style: TextStyle(
                  fontSize: 12.5,
                  color: on ? c.violet : c.ink,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                )),
          ]),
        ),
      ),
    );
  }
}
