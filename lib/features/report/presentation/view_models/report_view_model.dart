import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/image_model.dart';
import '../../../problem/models/m_problem_model.dart';

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
      await Future.delayed(const Duration(milliseconds: 300));
      problemTypes = MProblemModel.mockList();
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
    if (images.isEmpty) return 'กรุณาแนบรูปภาพอย่างน้อย 1 รูป';
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
      // API multipart upload would go here
      for (var i = 0; i <= 100; i += 20) {
        await Future.delayed(const Duration(milliseconds: 150));
        sendProgress = i / 100;
        notifyListeners();
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
