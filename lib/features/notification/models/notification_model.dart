class NotificationModel {
  final String id;
  final String title;
  final String desc;
  final bool isActive;
  final DateTime created;
  bool isRead;

  NotificationModel({
    required this.id,
    required this.title,
    required this.desc,
    required this.isActive,
    required this.created,
    this.isRead = false,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['uniqueId'] as String? ?? json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      desc: json['desc'] as String? ?? '',
      isActive: json['isActive'] as bool? ?? true,
      created: json['created'] != null
          ? DateTime.tryParse(json['created'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isRead: false,
    );
  }

}
