import 'package:flutter/material.dart';
import '../../models/problem_model.dart';

class ProblemViewModel extends ChangeNotifier {
  bool isLoading = false;
  List<ProblemModel> problems = [];
  String? errorMessage;

  Future<void> loadProblems({String? token, String? assetNo}) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      // API call would go here
      await Future.delayed(const Duration(milliseconds: 400));
      problems = ProblemModel.mockList();
    } catch (_) {
      problems = ProblemModel.mockList();
    }

    isLoading = false;
    notifyListeners();
  }
}
