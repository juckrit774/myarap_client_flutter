/// การแจ้งเตือนจาก GET /v3/api/notifications
///
/// ⚠️ **field ชุดนี้เปลี่ยนใหม่ทั้งหมด (2026-08-06)** — ของเดิมเป็น `uniqueId/title/desc/isActive`
/// ซึ่งไม่ตรงกับ backend เลยสักตัว (backend คืน `id/kind/message/ticketId/ticketNum/at`)
/// ตอนนั้นไม่มีใครจับได้เพราะ view model เป็น stub คืนลิสต์ว่างเสมอ ไม่เคยยิง API จริง
class NotificationModel {
  final String id;

  /// ชนิดของเหตุการณ์ เช่น `ticket_assigned` `resolve` `close` `sla_breach`
  /// ใช้เลือกไอคอน/สี และตั้งหัวข้อภาษาไทย (backend ส่งมาเป็น code ล้วน)
  final String kind;
  final String message;
  final String ticketId;
  final String ticketNum;
  final DateTime at;
  bool isRead;

  NotificationModel({
    required this.id,
    required this.kind,
    required this.message,
    required this.ticketId,
    required this.ticketNum,
    required this.at,
    this.isRead = false,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) =>
      NotificationModel(
        id: json['id']?.toString() ?? '',
        kind: json['kind'] as String? ?? '',
        message: json['message'] as String? ?? '',
        ticketId: json['ticketId'] as String? ?? '',
        ticketNum: json['ticketNum'] as String? ?? '',
        at: DateTime.tryParse(json['at']?.toString() ?? '')?.toLocal() ??
            DateTime.now(),
      );

  /// หัวข้อภาษาไทยของ kind — backend ไม่ได้ส่ง title มาให้ (มีแต่ message ที่เป็นประโยคเต็ม)
  String get title => switch (kind) {
        'new_ticket' => 'เรื่องใหม่',
        'ticket_assigned' => 'มอบหมายงานแล้ว',
        'start_work' => 'ช่างเริ่มดำเนินการ',
        'resolve' => 'ช่างแก้ไขเสร็จแล้ว',
        'close' => 'ปิดเรื่องแล้ว',
        'cancel' => 'ยกเลิกเรื่อง',
        'reopen' => 'เปิดเรื่องใหม่',
        'sla_breach' => 'เกินเวลาที่กำหนด',
        'sla_escalated' => 'ยกระดับความเร่งด่วน',
        'eol_alert' => 'ซอฟต์แวร์ใกล้หมดอายุ',
        _ => 'การแจ้งเตือน',
      };
}
