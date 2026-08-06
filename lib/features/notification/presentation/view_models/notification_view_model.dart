import 'package:flutter/material.dart';

import '../../../../core/services/network_manager.dart';
import '../../models/notification_model.dart';

/// ⚠️ เดิมทั้งคลาสนี้เป็น stub (`// TODO: replace with real API call` แล้ว `notifications = []`)
/// — หน้าการแจ้งเตือนของ agent จึงว่างเปล่ามาตลอดโดยไม่มีอะไรบอกว่ามันยังไม่ได้ต่อ
///
/// ตอนนี้ยิง `/v3/api/notifications` จริง ซึ่งคืน **การแจ้งเตือนของเจ้าของเครื่อง**
/// (ชุดเดียวกับที่เขาเห็นบนเว็บ) — เครื่องที่ยังไม่มีเจ้าของจะได้ลิสต์ว่าง ไม่ใช่ error
class NotificationViewModel extends ChangeNotifier {
  bool isLoading = false;
  String? errorMessage;
  List<NotificationModel> notifications = [];

  int get unreadCount => notifications.where((n) => !n.isRead).length;

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final data = await NetworkManager.instance.getV3('/v3/api/notifications');
      final list = data['data'] as List<dynamic>? ?? [];
      notifications = list
          .map((e) => NotificationModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // เก็บของเดิมไว้ ไม่ล้างทิ้ง — เน็ตสะดุดรอบเดียวไม่ควรทำให้รายการที่อ่านค้างอยู่หายไป
      errorMessage = 'โหลดการแจ้งเตือนไม่ได้';
    }

    isLoading = false;
    notifyListeners();
  }

  /// mark read ฝั่ง UI ทันทีแล้วค่อยยิง API — ผู้ใช้ไม่ต้องรอ round-trip
  /// (พลาดก็แค่จุดสีค้าง รอบโหลดถัดไปจะตรงเอง)
  Future<void> markAsRead(String id) async {
    final i = notifications.indexWhere((n) => n.id == id);
    if (i == -1 || notifications[i].isRead) return;
    notifications[i].isRead = true;
    notifyListeners();
    try {
      await NetworkManager.instance
          .postV3('/v3/api/notifications/$id/read', const {});
    } catch (_) {}
  }

  Future<void> markAllAsRead() async {
    if (unreadCount == 0) return;
    for (final n in notifications) {
      n.isRead = true;
    }
    notifyListeners();
    try {
      await NetworkManager.instance
          .postV3('/v3/api/notifications/read-all', const {});
    } catch (_) {}
  }
}
