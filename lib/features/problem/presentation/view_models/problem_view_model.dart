import 'package:flutter/material.dart';
import '../../models/problem_model.dart';
import '../../../../core/services/network_manager.dart';

class ProblemViewModel extends ChangeNotifier {
  bool isLoading = false;
  List<ProblemModel> problems = [];
  String? errorMessage;

  /// โหลด ticket list ของ device นี้จาก GET /v3/api/tickets
  Future<void> loadProblems() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final data = await NetworkManager.instance.getV3('/v3/api/tickets');
      final list = data['data'] as List<dynamic>? ?? [];
      problems = list
          .map((e) => ProblemModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      problems = [];
      errorMessage = 'ไม่สามารถโหลดรายการได้';
    }

    isLoading = false;
    notifyListeners();
  }
}
