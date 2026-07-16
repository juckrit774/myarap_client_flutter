import 'package:flutter/material.dart';
import '../../models/notification_model.dart';

class NotificationViewModel extends ChangeNotifier {
  bool isLoading = false;
  List<NotificationModel> notifications = [];

  int get unreadCount => notifications.where((n) => !n.isRead).length;

  Future<void> loadNotifications({String? token}) async {
    isLoading = true;
    notifyListeners();

    // TODO: replace with real API call
    notifications = [];

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
