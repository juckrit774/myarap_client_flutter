import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/image_model.dart';
import '../../../problem/models/m_problem_model.dart';
import '../../../../core/services/network_manager.dart';
import '../../../../core/models/base_request_model.dart';

class ReportViewModel extends ChangeNotifier {
  bool isLoading = false;
  bool isSending = false;
  double sendProgress = 0;

  List<MProblemModel> problemTypes = [];
  String remark = '';
  List<ImageModel> images = [];

  List<MProblemModel> get selectedProblems =>
      problemTypes.where((p) => p.isSelected).toList();

  Future<void> loadProblemTypes({String? token}) async {
    isLoading = true;
    notifyListeners();

    try {
      final response = await NetworkManager.instance.request<List<MProblemModel>>(
        request: BaseRequestModel(
          module: 'ProblemTracking',
          target: 'MProblem',
          token: token,
          data: {},
        ),
        parseEntries: (json) {
          if (json is List) {
            return json.map((e) => MProblemModel.fromJson(e as Map<String, dynamic>)).toList();
          }
          return [];
        },
        url: '/v2/api/Select',
      );
      if (response.isSuccess && response.entries != null) {
        problemTypes = response.entries!;
      } else {
        problemTypes = MProblemModel.mockList();
      }
    } catch (_) {
      problemTypes = MProblemModel.mockList();
    }

    isLoading = false;
    notifyListeners();
  }

  void toggleProblem(String id) {
    final index = problemTypes.indexWhere((p) => p.id == id);
    if (index != -1) {
      problemTypes[index].toggle();
      notifyListeners();
    }
  }

  void setRemark(String value) {
    remark = value;
    notifyListeners();
  }

  Future<void> pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'gif'],
      allowMultiple: true,
    );
    if (result != null) {
      for (final file in result.files) {
        if (file.path != null) {
          images.add(ImageModel(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            path: file.path!,
          ));
        }
      }
      notifyListeners();
    }
  }

  void removeImage(String id) {
    images.removeWhere((img) => img.id == id);
    notifyListeners();
  }

  String? validate() {
    if (selectedProblems.isEmpty) return 'กรุณาเลือกประเภทปัญหาอย่างน้อย 1 รายการ';
    final requireRemark = selectedProblems.any((p) => p.requireRemark);
    if (requireRemark && remark.trim().isEmpty) return 'กรุณากรอกหมายเหตุสำหรับปัญหาที่เลือก';
    return null;
  }

  Future<bool> sendReport({
    required String token,
    required String assetNo,
    void Function(String message)? onError,
  }) async {
    final error = validate();
    if (error != null) {
      onError?.call(error);
      return false;
    }

    isSending = true;
    sendProgress = 0;
    notifyListeners();

    try {
      // Step 1: Create problem record
      final createResponse = await NetworkManager.instance.request<Map<String, dynamic>>(
        request: BaseRequestModel(
          module: 'ProblemTracking',
          target: 'CreateProblem',
          token: token,
          data: {
            'assetNo': assetNo,
            'problems': selectedProblems.map((p) => p.id).toList(),
            'remark': remark,
          },
        ),
        parseEntries: (json) => json is Map<String, dynamic> ? json : null,
        url: '/v2/api/Insert',
      );

      if (createResponse.status == 401) {
        isSending = false;
        notifyListeners();
        NetworkManager.onUnauthorized?.call();
        return false;
      }

      if (!createResponse.isSuccess) {
        onError?.call(createResponse.message.isNotEmpty ? createResponse.message : 'ส่งรายงานไม่สำเร็จ');
        isSending = false;
        notifyListeners();
        return false;
      }

      // Step 2: Upload images if any (optional)
      if (images.isNotEmpty && createResponse.entries != null) {
        final problemId = createResponse.entries!['id']?.toString();
        if (problemId != null) {
          final multipartFiles = await Future.wait(
            images.map((img) => MultipartFile.fromFile(img.path, filename: img.fileName)),
          );
          await NetworkManager.instance.uploadMultipart<dynamic>(
            fields: {
              'module': 'ProblemTracking',
              'target': 'UploadProblemImage',
              'token': token,
              'problem_id': problemId,
            },
            files: multipartFiles,
            parseEntries: (json) => json,
            onProgress: (sent, total) {
              sendProgress = total > 0 ? sent / total : 0;
              notifyListeners();
            },
          );
        }
      }

      _reset();
      isSending = false;
      notifyListeners();
      return true;
    } catch (e) {
      isSending = false;
      notifyListeners();
      onError?.call('ส่งรายงานไม่สำเร็จ กรุณาลองใหม่');
      return false;
    }
  }

  void _reset() {
    for (final p in problemTypes) {
      p.isSelected = false;
    }
    remark = '';
    images = [];
    sendProgress = 0;
  }
}
