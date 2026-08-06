import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/config/app_colors.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/services/network_manager.dart';
import '../../../../core/storage/cache_manager.dart';
import '../../../../shared/widgets/app_shell.dart';
import '../../../../shared/widgets/ticket_style.dart';
import '../../../home/presentation/view_models/home_view_model.dart';
import '../../../qrcode/presentation/screens/qrcode_screen.dart';

/// หน้า "ตั้งค่า"
///
/// ของใหม่คือ **การ์ดบัญชีผู้ใช้** — เดิม agent ไม่เคยบอกเลยว่าเครื่องนี้ผูกกับบัญชีไหน
/// ทั้งที่เป็นคำถามแรกเวลาโทรหา IT ("เครื่องคุณขึ้นชื่อใครในระบบ?") ผู้ใช้ต้องไปเปิดเว็บดูเอง
class SettingsSection extends StatefulWidget {
  const SettingsSection({super.key, required this.vm});
  final HomeViewModel vm;

  @override
  State<SettingsSection> createState() => _SettingsSectionState();
}

class _SettingsSectionState extends State<SettingsSection> {
  final _urlCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadUrl();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUrl() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      _urlCtrl.text = prefs.getString('server_url') ?? AppConfig.baseUrl;
      setState(() {});
    }
  }

  Future<void> _saveUrl() async {
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', _urlCtrl.text.trim());
    await NetworkManager.instance.updateBaseUrl();
    if (!mounted) return;
    setState(() => _saving = false);
    _toast('บันทึกที่อยู่เซิร์ฟเวอร์แล้ว');
  }

  Future<void> _clearCache() async {
    final c = AppColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: Text('ล้างข้อมูลในเครื่อง',
            style: TextStyle(fontSize: 15, color: c.ink)),
        content: Text(
          'จะลบ token และข้อมูลที่แคชไว้ทั้งหมด — แอปจะลงทะเบียนเครื่องใหม่ให้เองเมื่อเปิดครั้งถัดไป',
          style: TextStyle(fontSize: 12.5, color: c.dim, height: 1.5),
        ),
        actions: [
          GhostButton(label: 'ยกเลิก', onPressed: () => Navigator.pop(ctx, false)),
          GhostButton(
              label: 'ล้างข้อมูล',
              color: c.crit,
              onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok != true) return;
    await CacheManager.clear();
    _toast('ล้างข้อมูลในเครื่องแล้ว');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      children: [
        const SectionHeader(title: 'ตั้งค่า'),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _accountCard(c)),
          const SizedBox(width: 11),
          Expanded(child: _serverCard(c)),
        ]),
        const SizedBox(height: 11),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _dataCard(c)),
          const SizedBox(width: 11),
          Expanded(child: _aboutCard(c)),
        ]),
      ],
    );
  }

  Widget _accountCard(AppPalette c) {
    final vm = widget.vm;
    final hasOwner = vm.ownerName.isNotEmpty;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CardTitle('บัญชีผู้ใช้'),
        if (!hasOwner)
          Text(
            'เครื่องนี้ยังไม่ได้ผูกกับบัญชีผู้ใช้ในระบบ — แจ้งทีม IT เพื่อกำหนดเจ้าของเครื่อง',
            style: TextStyle(fontSize: 12, color: c.dim, height: 1.5),
          )
        else ...[
          Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                  gradient: AppColors.brandGradient, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(vm.ownerName.trim()[0].toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(vm.ownerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600, color: c.ink)),
                if (vm.ownerAccount.isNotEmpty)
                  Text(vm.ownerAccount,
                      style: TextStyle(fontSize: 11.5, color: c.dim)),
              ]),
            ),
            if (vm.ownerRole.isNotEmpty)
              StatusPill(vm.ownerRole, color: c.violet, dot: false),
          ]),
          const SizedBox(height: 12),
          // ผู้ใช้ทั่วไปเข้าใจว่า role ในนี้คือ "สิทธิ์ที่ทำได้ในโปรแกรมนี้" ซึ่งไม่ใช่ —
          // งานจัดการทั้งหมดอยู่บนเว็บ agent เป็นแค่ตัวรายงาน + แจ้งเรื่อง
          Text('สิทธิ์นี้ใช้บนเว็บ MYARAP — เปลี่ยนได้ที่ทีม IT เท่านั้น',
              style: TextStyle(fontSize: 11, color: c.dim)),
        ],
        const SizedBox(height: 12),
        KvRow('รหัสครุภัณฑ์', vm.isRegistered ? vm.assetNo : 'รออนุมัติ',
            valueColor: vm.isRegistered ? null : c.warn),
        KvRow('ชื่อเครื่อง', vm.userName),
      ]),
    );
  }

  Widget _serverCard(AppPalette c) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CardTitle('การเชื่อมต่อ'),
          TextField(
            controller: _urlCtrl,
            style: TextStyle(fontSize: 12.5, color: c.ink),
            decoration: appInput(c, AppConfig.baseUrl),
          ),
          const SizedBox(height: 6),
          Text('ที่อยู่เซิร์ฟเวอร์ MYARAP — เปลี่ยนเมื่อทีม IT แจ้งเท่านั้น',
              style: TextStyle(fontSize: 11, color: c.dim)),
          const SizedBox(height: 11),
          Row(children: [
            PrimaryButton(
              label: 'บันทึก',
              busy: _saving,
              onPressed: _saving ? null : _saveUrl,
            ),
            const SizedBox(width: 8),
            GhostButton(
              label: 'QR ยืนยันตัวตน',
              icon: Icons.qr_code_2,
              onPressed: () => showDialog(
                context: context,
                builder: (_) =>
                    QRCodeDialog(data: widget.vm.accessToken ?? 'MYARAP'),
              ),
            ),
          ]),
        ]),
      );

  Widget _dataCard(AppPalette c) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CardTitle('ข้อมูลในเครื่อง'),
          Text('ล้าง token และข้อมูลที่แคชไว้ ใช้เมื่อเชื่อมต่อไม่ได้และทีม IT แนะนำให้ทำ',
              style: TextStyle(fontSize: 12, color: c.dim, height: 1.5)),
          const SizedBox(height: 11),
          GhostButton(
            label: 'ล้างข้อมูล',
            icon: Icons.delete_outline,
            color: c.crit,
            onPressed: _clearCache,
          ),
        ]),
      );

  Widget _aboutCard(AppPalette c) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CardTitle('เกี่ยวกับ'),
          KvRow('เวอร์ชัน', '${AppConfig.appVersion} (${AppConfig.buildNumber})'),
          KvRow('โหมดสี', c.isDark ? 'มืด (ตามระบบ)' : 'สว่าง (ตามระบบ)'),
          const SizedBox(height: 11),
          GhostButton(
            label: 'สัญญาอนุญาตโอเพนซอร์ส',
            icon: Icons.code,
            onPressed: () => showLicensePage(
              context: context,
              applicationName: AppConfig.appName,
              applicationVersion: AppConfig.appVersion,
            ),
          ),
        ]),
      );
}
