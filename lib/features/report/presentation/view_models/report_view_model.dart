import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/image_model.dart';
import '../../../problem/models/m_problem_model.dart';
import '../../../../core/services/network_manager.dart';

class ReportViewModel extends ChangeNotifier {
  bool isLoading = false;
  bool isSending = false;
  double sendProgress = 0;

  List<MProblemModel> problemTypes = [];
  String remark = '';
  List<ImageModel> images = [];

  List<MProblemModel> get selectedProblems =>
      problemTypes.where((p) => p.isSelected).toList();

  /// โหลด problem types จาก GET /v3/api/problems
  Future<void> loadProblemTypes() async {
    if (isLoading) return;
    isLoading = true;
    notifyListeners();

    try {
      final data = await NetworkManager.instance.getV3('/v3/api/problems');
      final list = data['data'] as List<dynamic>? ?? [];
      final seen = <String>{};
      problemTypes = list
          .map((e) => MProblemModel.fromJson(e as Map<String, dynamic>))
          .where((p) => seen.add(p.id))
          .toList();
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

  /// ส่ง ticket ผ่าน POST /v3/api/tickets
  Future<bool> sendReport({
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
      final body = <String, dynamic>{
        'problems': selectedProblems.map((p) => p.id).toList(),
        'description': remark,
      };
      // ถ้า remark ไม่ว่างใช้เป็น title ด้วย (V3 auto-fill title จาก problems[] ถ้าไม่มี)
      if (remark.trim().isNotEmpty) {
        body['title'] = remark.trim();
      }

      final resp = await NetworkManager.instance.postV3('/v3/api/tickets', body);
      final ticketId = resp['id']?.toString();

      // อัปโหลดรูปภาพ (ยังใช้ V2 Upload endpoint หรือข้ามไปก่อน)
      // TODO: V3 ยังไม่มี image upload endpoint — ข้ามไปก่อน
      if (images.isNotEmpty && ticketId != null) {
        sendProgress = 0.5;
        notifyListeners();
        // placeholder: image upload จะเพิ่มใน V3 ภายหลัง
      }

      sendProgress = 1.0;
      _reset();
      isSending = false;
      notifyListeners();
      return true;
    } catch (e) {
      if (e.toString().contains('unauthorized')) {
        NetworkManager.onUnauthorized?.call();
      } else {
        onError?.call('ส่งรายงานไม่สำเร็จ กรุณาลองใหม่');
      }
      isSending = false;
      notifyListeners();
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
