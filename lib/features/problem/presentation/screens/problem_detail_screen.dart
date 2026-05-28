import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/config/app_colors.dart';
import '../../../../shared/widgets/app_header.dart';
import '../../models/problem_model.dart';

class ProblemDetailScreen extends StatelessWidget {
  final ProblemModel problem;

  const ProblemDetailScreen({super.key, required this.problem});

  Color _statusColor(String s) => switch (s) {
        'Open' || 'Opened' => Colors.red,
        'In Progress' || 'Processing' => AppColors.orange,
        'Resolved' || 'Closed' => Colors.green,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgColor,
      appBar: const AppHeader(
        showBackButton: true,
        title: Text(
          'รายละเอียดปัญหา',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status + icon
            Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: _statusColor(problem.currentStatus).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        problem.currentStatus,
                        style: TextStyle(
                          color: _statusColor(problem.currentStatus),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Icon(Icons.computer, size: 80, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text(
                      'Asset: ${problem.assetNo}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.deepPurple,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Detail rows
            Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    _DetailRow('เลขที่เคส', problem.problemNo),
                    const Divider(height: 1, indent: 16),
                    if (problem.computerName != null)
                      _DetailRow('ชื่อเครื่อง', problem.computerName!),
                    if (problem.computerName != null)
                      const Divider(height: 1, indent: 16),
                    _DetailRow('ผู้แจ้ง', problem.reporter),
                    const Divider(height: 1, indent: 16),
                    _DetailRow('วันที่แจ้ง', problem.formattedDate),
                    const Divider(height: 1, indent: 16),
                    _DetailRow('ปัญหา', problem.problemList.join(', ')),
                    if (problem.remark.isNotEmpty) ...[
                      const Divider(height: 1, indent: 16),
                      _DetailRow('หมายเหตุ', problem.remark),
                    ],
                    if (problem.openChatLink != null) ...[
                      const Divider(height: 1, indent: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Text('OpenChat', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                            const Spacer(),
                            TextButton(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: problem.openChatLink!));
                              },
                              child: const Text('คัดลอกลิงก์'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Images
            if (problem.imageList.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'รูปภาพ',
                style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.deepPurple),
              ),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                children: problem.imageList
                    .map((url) => ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(url, fit: BoxFit.cover),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
