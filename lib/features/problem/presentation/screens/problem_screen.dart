import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/config/app_colors.dart';
import '../../../../shared/widgets/app_header.dart';
import '../../models/problem_model.dart';
import '../view_models/problem_view_model.dart';
import 'problem_detail_screen.dart';

class ProblemScreen extends StatelessWidget {
  // V3: ไม่ต้องส่ง token/assetNo — NetworkManager จัดการ Bearer JWT เอง
  const ProblemScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ProblemViewModel()..loadProblems(),
      child: const _ProblemView(),
    );
  }
}

class _ProblemView extends StatelessWidget {
  const _ProblemView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProblemViewModel>();
    return Scaffold(
      backgroundColor: AppColors.bgColor,
      appBar: const AppHeader(
        showBackButton: true,
        title: Text(
          'ปัญหาที่แจ้ง',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      body: vm.isLoading
          ? const Center(child: CircularProgressIndicator())
          : vm.problems.isEmpty
              ? _emptyState()
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: vm.problems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _ProblemCard(
                    problem: vm.problems[i],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProblemDetailScreen(problem: vm.problems[i]),
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text('ไม่มีปัญหาที่แจ้ง', style: TextStyle(color: Colors.grey[500])),
        ],
      ),
    );
  }
}

class _ProblemCard extends StatelessWidget {
  const _ProblemCard({required this.problem, required this.onTap});
  final ProblemModel problem;
  final VoidCallback onTap;

  Color _statusColor(String status) => switch (status) {
        'new' || 'Open' || 'Opened' => Colors.red,
        'assigned' => AppColors.orange,
        'in_progress' || 'In Progress' || 'Processing' => AppColors.opaPurple,
        'resolved' || 'Resolved' => Colors.teal,
        'closed' || 'Closed' => Colors.green,
        'cancelled' => Colors.grey,
        _ => Colors.grey,
      };

  String _statusLabel(String status) => switch (status) {
        'new' => 'รอดำเนินการ',
        'assigned' => 'มอบหมายแล้ว',
        'in_progress' => 'กำลังดำเนินการ',
        'resolved' => 'แก้ไขแล้ว',
        'closed' => 'ปิดแล้ว',
        'cancelled' => 'ยกเลิก',
        _ => status,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    problem.problemNo,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppColors.mainPurple,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor(problem.currentStatus).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _statusLabel(problem.currentStatus),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _statusColor(problem.currentStatus),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (problem.problemList.isNotEmpty)
                Text(
                  problem.problemList.first,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              if (problem.assetNo.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Asset: ${problem.assetNo}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                problem.formattedDate,
                style: TextStyle(fontSize: 12, color: Colors.grey[400]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
