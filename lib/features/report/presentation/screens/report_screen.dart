import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/config/app_colors.dart';
import '../../../../shared/widgets/app_header.dart';
import '../../../../shared/widgets/loading_overlay.dart';
import '../view_models/report_view_model.dart';
import 'select_problem_screen.dart';

class ReportScreen extends StatelessWidget {
  // V3: ไม่ต้องส่ง token/assetNo — NetworkManager จัดการ Bearer JWT เอง
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ReportViewModel()..loadProblemTypes(),
      child: const _ReportView(),
    );
  }
}

class _ReportView extends StatefulWidget {
  const _ReportView();

  @override
  State<_ReportView> createState() => _ReportViewState();
}

class _ReportViewState extends State<_ReportView> {
  final _remarkController = TextEditingController();

  @override
  void dispose() {
    _remarkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReportViewModel>();
    return Scaffold(
      backgroundColor: AppColors.bgColor,
      appBar: const AppHeader(
        showBackButton: true,
        title: Text(
          'แจ้งปัญหา',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProblemSelector(context, vm),
                const SizedBox(height: 16),
                _buildRemarkField(context, vm),
                const SizedBox(height: 16),
                _buildImageSection(context, vm),
                const SizedBox(height: 24),
                _buildSendButton(context, vm),
                const SizedBox(height: 16),
              ],
            ),
          ),
          if (vm.isSending) const LoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildProblemSelector(BuildContext context, ReportViewModel vm) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ประเภทปัญหา',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.deepPurple),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.add, color: AppColors.mainPurple),
              label: const Text('เลือกปัญหา', style: TextStyle(color: AppColors.mainPurple)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.mainPurple),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: vm.isLoading
                  ? null
                  : () => _showProblemPicker(context, vm),
            ),
            if (vm.selectedProblems.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: vm.selectedProblems
                    .map((p) => Chip(
                          label: Text(p.name, style: const TextStyle(fontSize: 12)),
                          backgroundColor: AppColors.mainPurple.withOpacity(0.1),
                          side: const BorderSide(color: AppColors.mainPurple, width: 0.5),
                          deleteIcon: const Icon(Icons.close, size: 14),
                          onDeleted: () => vm.toggleProblem(p.id),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showProblemPicker(BuildContext context, ReportViewModel vm) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SelectProblemScreen(
        problems: vm.problemTypes,
        onToggle: vm.toggleProblem,
      ),
    );
  }

  Widget _buildRemarkField(BuildContext context, ReportViewModel vm) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'หมายเหตุ',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.deepPurple),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _remarkController,
              maxLines: 5,
              minLines: 3,
              decoration: InputDecoration(
                hintText: 'อธิบายปัญหาเพิ่มเติม...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: AppColors.bgColor,
              ),
              onChanged: vm.setRemark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSection(BuildContext context, ReportViewModel vm) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'รูปภาพ',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.deepPurple),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.image_outlined, color: AppColors.mainPurple),
              label: const Text('เลือกรูปภาพ', style: TextStyle(color: AppColors.mainPurple)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.mainPurple),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: vm.pickImage,
            ),
            if (vm.images.isNotEmpty) ...[
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                children: vm.images
                    .map((img) => Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(img.path),
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () => vm.removeImage(img.id),
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close, color: Colors.white, size: 14),
                                ),
                              ),
                            ),
                          ],
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSendButton(BuildContext context, ReportViewModel vm) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.mainPurple,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
        onPressed: vm.isSending
            ? null
            : () async {
                final success = await vm.sendReport(
                  onError: (msg) => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(msg),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  ),
                );
                if (success && context.mounted) {
                  _remarkController.clear();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('ส่งรายงานสำเร็จ'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  Navigator.pop(context);
                }
              },
        child: const Text(
          'ส่งรายงาน',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
