import 'package:flutter/material.dart';
import '../../models/notification_model.dart';

class NotificationViewModel extends ChangeNotifier {
  bool isLoading = false;
  List<NotificationModel> notifications = [];

  int get unreadCount => notifications.where((n) => !n.isRead).length;

  Future<void> loadNotifications({String? token}) async {
    isLoading = true;
    notifyListeners();

    try {
      // API call would go here
      // On failure, use mock data
      await Future.delayed(const Duration(milliseconds: 400));
      notifications = NotificationModel.mockList();
    } catch (_) {
      notifications = NotificationModel.mockList();
    }

    isLoading = false;
    notifyListeners();
  }

  void markAsRead(String id) {
    final index = notifications.indexWhere((n) => n.id == id);
    if (index != -1) {
      notifications[index].isRead = true;
      notifyListeners();
    }
  }

  void markAllAsRead() {
    for (final n in notifications) {
      n.isRead = true;
    }
    notifyListeners();
  }
}
