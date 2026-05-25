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

  // Mock data for development
  static List<NotificationModel> mockList() => [
        NotificationModel(
          id: '1',
          title: 'อัปเดตระบบสำเร็จ',
          desc: 'ข้อมูลอุปกรณ์ของคุณได้รับการอัปเดตเรียบร้อยแล้ว',
          isActive: true,
          created: DateTime.now().subtract(const Duration(minutes: 10)),
          isRead: false,
        ),
        NotificationModel(
          id: '2',
          title: 'แจ้งเตือนการบำรุงรักษา',
          desc: 'ระบบจะหยุดทำงานชั่วคราวเพื่อบำรุงรักษาในวันเสาร์ที่ 25 พฤษภาคม 2026 เวลา 22:00 น.',
          isActive: true,
          created: DateTime.now().subtract(const Duration(hours: 2)),
          isRead: false,
        ),
        NotificationModel(
          id: '3',
          title: 'พบปัญหาการเชื่อมต่อ',
          desc: 'อุปกรณ์ MacBook Pro ของคุณมีปัญหาการเชื่อมต่อเครือข่าย กรุณาตรวจสอบ',
          isActive: true,
          created: DateTime.now().subtract(const Duration(hours: 5)),
          isRead: true,
        ),
        NotificationModel(
          id: '4',
          title: 'รายงานประจำเดือนพร้อมแล้ว',
          desc: 'รายงานสรุปการใช้งานอุปกรณ์ประจำเดือนพฤษภาคม 2026 พร้อมดาวน์โหลดแล้ว',
          isActive: true,
          created: DateTime.now().subtract(const Duration(days: 1)),
          isRead: true,
        ),
        NotificationModel(
          id: '5',
          title: 'อัปเดต macOS พร้อมแล้ว',
          desc: 'macOS Sequoia 15.5 พร้อมสำหรับการติดตั้งบนอุปกรณ์ของคุณ',
          isActive: true,
          created: DateTime.now().subtract(const Duration(days: 2)),
          isRead: true,
        ),
      ];
}
