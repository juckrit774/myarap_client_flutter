import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/config/app_colors.dart';
import '../../../../shared/widgets/app_shell.dart';
import '../../data/models/device_model.dart';
import '../view_models/home_view_model.dart';

/// หน้า "เครื่องของฉัน" — หน้าแรกของ agent แบบ A
///
/// ออกแบบให้ตอบ **3 คำถามภายในวินาทีแรก**: เครื่องนี้ลงทะเบียนแล้วหรือยัง ·
/// ตอนนี้ติดต่อส่วนกลางได้ไหม · **มีอะไรค้างที่ฉันต้องทำหรือเปล่า**
/// ของเดิมเป็นรายการสเปกยาว ๆ ไล่ตั้งแต่ Hardware UUID ซึ่งผู้ใช้ทั่วไปไม่ได้เปิดมาอ่าน
class DeviceSection extends StatelessWidget {
  const DeviceSection({super.key, required this.vm, this.pendingCount = 0, this.onOpenPending});

  final HomeViewModel vm;

  /// จำนวนงานที่รอผู้ใช้ยืนยัน — ของใหม่ ตอนนี้ผู้ใช้ไม่มีทางรู้เลยว่ามีงานค้าง
  /// นอกจากจะเข้าไปไล่ดูในรายการปัญหาเอง
  final int pendingCount;
  final VoidCallback? onOpenPending;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final d = vm.deviceDetail;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      children: [
        SectionHeader(
          title: 'เครื่องของฉัน',
          subtitle: vm.assetNo.isEmpty ? null : vm.assetNo,
          trailing: Row(children: [
            StatusPill(
              vm.updateErrorMessage == null ? 'เชื่อมต่อแล้ว' : 'ติดต่อเซิร์ฟเวอร์ไม่ได้',
              color: vm.updateErrorMessage == null ? c.ok : c.warn,
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: vm.isLoading ? null : () => vm.refresh(),
              icon: const Icon(Icons.refresh, size: 15),
              label: const Text('อัปเดตเดี๋ยวนี้', style: TextStyle(fontSize: 11.5)),
              style: TextButton.styleFrom(foregroundColor: c.dim),
            ),
          ]),
        ),
        _statusRow(context),
        const SizedBox(height: 11),
        // สองการ์ดนี้กว้างเท่ากัน — หน้าต่าง 1280px รองรับสองคอลัมน์สบาย
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _deviceCard(context, d)),
          const SizedBox(width: 11),
          Expanded(child: _storageCard(context, d)),
        ]),
        const SizedBox(height: 11),
        _usbCard(context),
      ],
    );
  }

  Widget _statusRow(BuildContext context) {
    final c = AppColors.of(context);
    final seen = vm.lastUpdated;
    final ago = seen == null ? null : DateTime.now().difference(seen);
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const CardTitle('ลงทะเบียน'),
            Text(vm.assetNo.isEmpty ? 'รออนุมัติ' : 'พร้อมใช้งาน',
                style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                    color: vm.assetNo.isEmpty ? c.warn : c.ok)),
            const SizedBox(height: 4),
            Text(
              vm.assetNo.isEmpty
                  ? 'เครื่องนี้ส่งข้อมูลไปแล้ว รอทีม IT อนุมัติ'
                  : 'รหัสครุภัณฑ์ ${vm.assetNo}',
              style: TextStyle(fontSize: 11, color: c.dim),
            ),
          ]),
        ),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const CardTitle('ส่งข้อมูลล่าสุด'),
            Text(ago == null ? '—' : _ago(ago),
                style: TextStyle(
                    fontSize: 21, fontWeight: FontWeight.w600, color: c.ink)),
            const SizedBox(height: 4),
            Text(
              vm.updateErrorMessage != null
                  ? 'จะส่งให้อัตโนมัติเมื่อกลับมาออนไลน์'
                  : (seen == null
                      ? 'กำลังส่งครั้งแรก'
                      : 'ล่าสุด ${DateFormat('HH:mm').format(seen)} น.'),
              style: TextStyle(fontSize: 11, color: c.dim),
            ),
          ]),
        ),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: AppCard(
          accent: pendingCount > 0 ? c.warn : null,
          onTap: pendingCount > 0 ? onOpenPending : null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CardTitle('ต้องทำ', color: pendingCount > 0 ? c.warn : null),
            Text('$pendingCount รายการ',
                style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                    color: pendingCount > 0 ? c.warn : c.ink)),
            const SizedBox(height: 4),
            Text(
              pendingCount > 0 ? 'กดเพื่อไปยืนยันปิดงาน →' : 'ไม่มีอะไรค้าง',
              style: TextStyle(
                  fontSize: 11, color: pendingCount > 0 ? c.warn : c.dim),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _deviceCard(BuildContext context, DeviceDetail? d) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CardTitle('ข้อมูลเครื่อง'),
          KvRow('รุ่น', d?.modelName.isNotEmpty == true ? d!.modelName : '—'),
          KvRow('ระบบปฏิบัติการ', d?.osVersion.isNotEmpty == true ? d!.osVersion : '—'),
          KvRow('โปรเซสเซอร์', d?.processor.isNotEmpty == true ? d!.processor : '—'),
          KvRow('หน่วยความจำ', d?.memory.isNotEmpty == true ? d!.memory : '—'),
          KvRow('หมายเลขเครื่อง', d?.serialNumber.isNotEmpty == true ? d!.serialNumber : '—',
              mono: true),
        ]),
      );

  /// พื้นที่จัดเก็บ **ต่อพาร์ทิชัน** — ใช้ `volumes[]` ที่ agent ส่งอยู่แล้ว
  /// (agent รุ่นก่อน 2026-08-05 ไม่มี list นี้ → fallback เป็นไดรฟ์ระบบใบเดียว)
  Widget _storageCard(BuildContext context, DeviceDetail? d) {
    final c = AppColors.of(context);
    final vols = d?.volumes ?? const <VolumeInfo>[];
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CardTitle('พื้นที่จัดเก็บ'),
        if (vols.isEmpty && d != null && d.storageCapacityBytes > 0)
          _volBar(context, d.storageName.isEmpty ? 'ไดรฟ์ระบบ' : d.storageName, '',
              d.storageCapacityBytes - d.storageAvailableBytes, d.storageCapacityBytes)
        else if (vols.isEmpty)
          Text('—', style: TextStyle(fontSize: 12.5, color: c.dim))
        else
          for (final v in vols)
            _volBar(context, v.mount, v.name, v.totalBytes - v.freeBytes, v.totalBytes),
      ]),
    );
  }

  Widget _volBar(BuildContext context, String mount, String name, int used, int total) {
    final c = AppColors.of(context);
    final pct = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
    // ≥90% แดง · ≥75% เหลือง — เกณฑ์เดียวกับฝั่งเว็บ
    final col = pct >= .9 ? c.crit : (pct >= .75 ? c.warn : c.cyan);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(name.isEmpty ? mount : '$mount · $name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500, color: c.ink)),
          ),
          Text('${_gb(used)} / ${_gb(total)}',
              style: TextStyle(fontSize: 11.5, color: c.dim, fontFamily: 'monospace')),
        ]),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: c.soft,
            valueColor: AlwaysStoppedAnimation(col),
          ),
        ),
        if (pct >= .9) ...[
          const SizedBox(height: 4),
          Text('เหลือน้อย — เหลือ ${_gb(total - used)}',
              style: TextStyle(fontSize: 10.5, color: c.crit)),
        ],
      ]),
    );
  }

  Widget _usbCard(BuildContext context) {
    final c = AppColors.of(context);
    final allowed = vm.deviceDetail == null ? true : vm.usbAllowed;
    return AppCard(
      child: Row(children: [
        StatusPill(allowed ? 'USB อนุญาต' : 'USB ถูกบล็อก',
            color: allowed ? c.cyan : c.crit),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            allowed
                ? 'อุปกรณ์เก็บข้อมูลภายนอกใช้งานได้ตามนโยบายองค์กร'
                : 'อุปกรณ์เก็บข้อมูลภายนอกถูกปิดตามนโยบายองค์กร — ติดต่อทีม IT หากจำเป็นต้องใช้',
            style: TextStyle(fontSize: 12, color: c.dim),
          ),
        ),
      ]),
    );
  }

  static String _ago(Duration d) {
    if (d.inMinutes < 1) return 'เมื่อสักครู่';
    if (d.inMinutes < 60) return '${d.inMinutes} นาทีที่แล้ว';
    if (d.inHours < 24) return '${d.inHours} ชม.ที่แล้ว';
    return '${d.inDays} วันที่แล้ว';
  }

  static String _gb(int bytes) {
    final gb = bytes / 1073741824;
    return gb >= 1024
        ? '${(gb / 1024).toStringAsFixed(2)} TB'
        : '${gb.toStringAsFixed(0)} GB';
  }
}
