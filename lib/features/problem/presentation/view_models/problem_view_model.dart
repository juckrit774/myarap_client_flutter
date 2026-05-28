import 'package:flutter/material.dart';
import '../../models/problem_model.dart';
import '../../../../core/services/network_manager.dart';
import '../../../../core/models/base_request_model.dart';

class ProblemViewModel extends ChangeNotifier {
  bool isLoading = false;
  List<ProblemModel> problems = [];
  String? errorMessage;

  Future<void> loadProblems({String? token, String? assetNo}) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final response = await NetworkManager.instance.request<List<ProblemModel>>(
        request: BaseRequestModel(
          module: 'ProblemTracking',
          target: 'ClientProblemList',
          token: token,
          data: assetNo != null ? {'assetNo': assetNo} : {},
        ),
        parseEntries: (json) {
          if (json is List) {
            return json
                .map((e) => ProblemModel.fromJson(e as Map<String, dynamic>))
                .toList();
          }
          return [];
        },
        url: '/v2/api/Select',
      );

      if (response.isSuccess && response.entries != null) {
        problems = response.entries!;
      } else {
        problems = [];
        errorMessage = response.message.isNotEmpty ? response.message : 'โหลดข้อมูลไม่สำเร็จ';
      }
    } catch (_) {
      problems = [];
      errorMessage = 'ไม่สามารถเชื่อมต่อได้';
    }

    isLoading = false;
    notifyListeners();
  }
}
