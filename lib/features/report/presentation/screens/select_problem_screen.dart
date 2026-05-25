import 'package:flutter/material.dart';
import '../../../../core/config/app_colors.dart';
import '../../../problem/models/m_problem_model.dart';

class SelectProblemScreen extends StatefulWidget {
  final List<MProblemModel> problems;
  final void Function(String id) onToggle;

  const SelectProblemScreen({
    super.key,
    required this.problems,
    required this.onToggle,
  });

  @override
  State<SelectProblemScreen> createState() => _SelectProblemScreenState();
}

class _SelectProblemScreenState extends State<SelectProblemScreen> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              gradient: AppColors.headerGradient,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'เลือกประเภทปัญหา',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('เสร็จ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: widget.problems.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
              itemBuilder: (_, i) {
                final p = widget.problems[i];
                return ListTile(
                  leading: Icon(
                    p.isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                    color: p.isSelected ? AppColors.mainPurple : Colors.grey,
                  ),
                  title: Text(p.name),
                  onTap: () {
                    widget.onToggle(p.id);
                    setState(() {});
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
