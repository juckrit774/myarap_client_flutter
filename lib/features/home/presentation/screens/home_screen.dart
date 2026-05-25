import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/config/app_colors.dart';
import '../../../../shared/widgets/app_header.dart';
import '../../../../shared/widgets/loading_overlay.dart';
import '../view_models/home_view_model.dart';
import '../../../notification/presentation/screens/notification_screen.dart';
import '../../../problem/presentation/screens/problem_screen.dart';
import '../../../report/presentation/screens/report_screen.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import '../../../qrcode/presentation/screens/qrcode_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => HomeViewModel()..initialize(),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HomeViewModel>();
    return Scaffold(
      backgroundColor: AppColors.bgColor,
      appBar: _buildHeader(context, vm),
      body: Stack(
        children: [
          Column(
            children: [
              _UserSection(vm: vm),
              Expanded(child: _DeviceDetailsSection(vm: vm)),
              _ActionButtons(vm: vm),
            ],
          ),
          if (vm.isLoading) const LoadingOverlay(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildHeader(BuildContext context, HomeViewModel vm) {
    return AppHeader(
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Center(
            child: Text(
              'M',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'MYARAP',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          Text(
            'Asset: ${vm.assetNo}',
            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.qr_code, color: Colors.white),
          tooltip: 'QR Code',
          onPressed: () => _showQRCode(context, vm.token ?? ''),
        ),
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.white),
          tooltip: 'Notifications',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NotificationScreen(token: vm.token),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: Colors.white),
          tooltip: 'Settings',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  void _showQRCode(BuildContext context, String token) {
    showDialog(
      context: context,
      builder: (_) => QRCodeDialog(data: token.isEmpty ? 'MYARAP' : token),
    );
  }
}

// ─── User Section ────────────────────────────────────────────────────────────

class _UserSection extends StatelessWidget {
  const _UserSection({required this.vm});
  final HomeViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.mainPurple.withOpacity(0.15),
            child: const Icon(Icons.person, size: 32, color: AppColors.mainPurple),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                vm.userName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.deepPurple,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                vm.assetUpdatedAt != null
                    ? 'Asset updated: ${vm.assetUpdatedAt}'
                    : vm.lastUpdated != null
                        ? 'อัปเดตล่าสุด: ${DateFormat('dd MMM yyyy HH:mm').format(vm.lastUpdated!)}'
                        : 'กำลังโหลด...',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.mainPurple),
            tooltip: 'Refresh',
            onPressed: () => context.read<HomeViewModel>().refresh(),
          ),
        ],
      ),
    );
  }
}

// ─── Device Details ───────────────────────────────────────────────────────────

class _DeviceDetailsSection extends StatelessWidget {
  const _DeviceDetailsSection({required this.vm});
  final HomeViewModel vm;

  @override
  Widget build(BuildContext context) {
    final d = vm.deviceDetail;
    if (d == null) {
      return const Center(child: CircularProgressIndicator());
    }

    String orNA(String v) => v.isNotEmpty ? v : 'N/A';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Device Identity ──────────────────────────────────────────────
          _InfoCard(
            title: 'ข้อมูลอุปกรณ์',
            icon: Icons.computer,
            rows: [
              _InfoRow('Computer Name', orNA(d.localizedName.isNotEmpty ? d.localizedName : d.computerName)),
              _InfoRow('Full Device Name', orNA(d.hostName.replaceAll('.local', ''))),
              _InfoRow('User Name', orNA(d.fullUserName)),
              _InfoRow('Model', orNA(d.modelName)),
              _InfoRow('Model Identifier', orNA(d.modelIdentifier)),
              _InfoRow('Serial Number', orNA(d.serialNumber)),
              _InfoRow('Hardware UUID', orNA(d.hardwareUUID)),
            ],
          ),
          const SizedBox(height: 12),

          // ── CPU ──────────────────────────────────────────────────────────
          _InfoCard(
            title: 'ชิป / โปรเซสเซอร์',
            icon: Icons.memory,
            rows: [
              if (d.chip.isNotEmpty)
                _InfoRow('Chip', d.chip),
              if (d.processor.isNotEmpty)
                _InfoRow('Processor', d.processor),
              if (d.vendor.isNotEmpty)
                _InfoRow('Vendor', d.vendor),
              _InfoRow('Total Cores', orNA(d.totalCores)),
              _InfoRow('Architecture', orNA(d.cpuArchitecture)),
              if (d.cpuFrequency.isNotEmpty && d.cpuFrequency != '0')
                _InfoRow('Base Speed', '${(int.tryParse(d.cpuFrequency) ?? 0) ~/ 1000000} MHz'),
              if (d.cpuFrequencyMax.isNotEmpty && d.cpuFrequencyMax != '0')
                _InfoRow('Max Speed', '${(int.tryParse(d.cpuFrequencyMax) ?? 0) ~/ 1000000} MHz'),
            ],
          ),
          const SizedBox(height: 12),

          // ── Memory ───────────────────────────────────────────────────────
          _InfoCard(
            title: 'หน่วยความจำ',
            icon: Icons.storage,
            rows: [
              _InfoRow('ขนาด', orNA(d.memory)),
              if (d.memoryType.isNotEmpty)
                _InfoRow('Type', d.memoryType),
              if (d.memoryManufacturer.isNotEmpty)
                _InfoRow('Manufacturer', d.memoryManufacturer),
            ],
          ),
          const SizedBox(height: 12),

          // ── Storage ──────────────────────────────────────────────────────
          _InfoCard(
            title: 'พื้นที่จัดเก็บข้อมูล',
            icon: Icons.folder,
            rows: [
              if (d.storageName.isNotEmpty)
                _InfoRow('Device', d.storageName),
              if (d.storageType.isNotEmpty)
                _InfoRow('Type', d.storageType),
              _InfoRow('ทั้งหมด', d.storageTotal),
              _InfoRow('พื้นที่ว่าง', d.storageAvailable),
            ],
          ),
          const SizedBox(height: 12),

          // ── GPU ──────────────────────────────────────────────────────────
          if (d.gpu.isNotEmpty) ...[
            _InfoCard(
              title: 'กราฟิก',
              icon: Icons.monitor,
              rows: [
                _InfoRow('GPU', d.gpu),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // ── Displays ─────────────────────────────────────────────────────
          _InfoCard(
            title: 'จอแสดงผล',
            icon: Icons.tv,
            rows: d.displaysDetail.isEmpty
                ? [const _InfoRow('Display', 'N/A')]
                : [
                    ...d.displaysDetail.where((e) => e.builtin).toList().asMap().entries.map((entry) {
                      final i = entry.key;
                      final disp = entry.value;
                      final res = disp.resolutionX > 0 ? '${disp.resolutionX}×${disp.resolutionY}' : '';
                      final label = d.displaysDetail.where((e) => e.builtin).length > 1
                          ? 'Internal ${i + 1}'
                          : 'Internal';
                      return _InfoRow(label, res.isNotEmpty ? '${disp.name} ($res)' : disp.name);
                    }),
                    ...d.displaysDetail.where((e) => !e.builtin).toList().asMap().entries.map((entry) {
                      final i = entry.key;
                      final disp = entry.value;
                      final res = disp.resolutionX > 0 ? '${disp.resolutionX}×${disp.resolutionY}' : '';
                      final label = d.displaysDetail.where((e) => !e.builtin).length > 1
                          ? 'External ${i + 1}'
                          : 'External';
                      return _InfoRow(label, res.isNotEmpty ? '${disp.name} ($res)' : disp.name);
                    }),
                  ],
          ),
          const SizedBox(height: 12),

          // ── OS ───────────────────────────────────────────────────────────
          _InfoCard(
            title: 'ระบบปฏิบัติการ',
            icon: Icons.laptop_mac,
            rows: [
              _InfoRow('Version', orNA(d.systemVersion.isNotEmpty ? d.systemVersion : d.osVersion)),
              if (d.kernelVersion.isNotEmpty)
                _InfoRow('Kernel', d.kernelVersion),
              if (d.bootVolume.isNotEmpty)
                _InfoRow('Boot Volume', d.bootVolume),
              if (d.bootMode.isNotEmpty)
                _InfoRow('Boot Mode', d.bootMode),
              if (d.timeSinceBoot.isNotEmpty)
                _InfoRow('Uptime', d.timeSinceBoot),
              if (d.firmwareVersion.isNotEmpty)
                _InfoRow('Firmware', d.firmwareVersion),
            ],
          ),
          const SizedBox(height: 12),

          // ── Network ──────────────────────────────────────────────────────
          _InfoCard(
            title: 'เครือข่าย',
            icon: Icons.wifi,
            rows: [
              _InfoRow('IP Address', orNA(d.ipAddress)),
            ],
          ),

          // ── Applications count ────────────────────────────────────────
          if (d.applications.isNotEmpty) ...[
            const SizedBox(height: 12),
            _InfoCard(
              title: 'แอปพลิเคชัน',
              icon: Icons.apps,
              rows: [
                _InfoRow('ติดตั้งแล้ว', '${d.applications.length} apps'),
              ],
            ),
          ],

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.icon,
    required this.rows,
  });

  final String title;
  final IconData icon;
  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(icon, size: 16, color: AppColors.mainPurple),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.deepPurple,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...rows.map((row) => row.build()),
        ],
      ),
    );
  }
}

class _InfoRow {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  Widget build() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Action Buttons ───────────────────────────────────────────────────────────

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({required this.vm});
  final HomeViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.report_problem_outlined, color: AppColors.mainPurple),
              label: const Text('ปัญหาที่แจ้ง', style: TextStyle(color: AppColors.mainPurple)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.mainPurple),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProblemScreen(
                    token: vm.token,
                    assetNo: vm.assetNo,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.send_outlined, color: Colors.white),
              label: const Text('แจ้งปัญหา', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.mainPurple,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReportScreen(
                    token: vm.token ?? '',
                    assetNo: vm.assetNo,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
