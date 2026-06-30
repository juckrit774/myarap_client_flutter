import 'package:intl/intl.dart';

class ProblemModel {
  final String id;
  final String problemNo;
  final String assetNo;
  final List<String> problemList;
  final List<String> imageList;
  final String remark;
  final String reporter;
  final DateTime created;
  final String currentStatus;
  final String? openChatLink;
  final String? computerName;

  const ProblemModel({
    required this.id,
    required this.problemNo,
    required this.assetNo,
    required this.problemList,
    required this.imageList,
    required this.remark,
    required this.reporter,
    required this.created,
    required this.currentStatus,
    this.openChatLink,
    this.computerName,
  });

  /// รองรับทั้ง V2 format และ V3 ticket format `{id, number, title, status, priority, createdAt}`
  factory ProblemModel.fromJson(Map<String, dynamic> json) {
    // V3 ticket fields
    final v3Id = json['id']?.toString();
    final v3Number = json['number'] as String?;
    final v3Title = json['title'] as String?;
    final v3Status = json['status'] as String?;
    final v3CreatedAt = json['createdAt'] as String?;

    return ProblemModel(
      id: v3Id ?? json['uniqueId']?.toString() ?? '',
      problemNo: v3Number ?? json['problemNo'] as String? ?? '',
      assetNo: json['assetNo'] as String? ?? '',
      problemList: v3Title != null
          ? [v3Title]
          : (json['problemList'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [],
      imageList: (json['imageList'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      remark: json['remark'] as String? ?? json['description'] as String? ?? '',
      reporter: json['reporter']?.toString() ?? json['requesterId']?.toString() ?? '',
      created: (v3CreatedAt ?? json['created'])?.toString() != null
          ? DateTime.tryParse((v3CreatedAt ?? json['created']).toString()) ?? DateTime.now()
          : DateTime.now(),
      currentStatus: v3Status ?? json['currentStatus'] as String? ?? 'Open',
      openChatLink: json['openChatLink'] as String?,
      computerName: json['computerName'] as String?,
    );
  }

  String get formattedDate =>
      DateFormat('dd MMM yyyy HH:mm').format(created);

  static List<ProblemModel> mockList() => [
        ProblemModel(
          id: '1',
          problemNo: 'CASE-2026-001',
          assetNo: 'AST-00142',
          problemList: ['หน้าจอมีปัญหา', 'เครื่องร้อนผิดปกติ'],
          imageList: [],
          remark: 'หน้าจอกระพริบเป็นช่วง ๆ ขณะใช้งาน',
          reporter: 'John Doe',
          created: DateTime.now().subtract(const Duration(days: 1)),
          currentStatus: 'Open',
          computerName: 'MacBook Pro',
        ),
        ProblemModel(
          id: '2',
          problemNo: 'CASE-2026-002',
          assetNo: 'AST-00142',
          problemList: ['Wi-Fi เชื่อมต่อไม่ได้'],
          imageList: [],
          remark: 'Wi-Fi หลุดบ่อยมากโดยไม่มีสาเหตุ',
          reporter: 'John Doe',
          created: DateTime.now().subtract(const Duration(days: 3)),
          currentStatus: 'In Progress',
          computerName: 'MacBook Pro',
        ),
        ProblemModel(
          id: '3',
          problemNo: 'CASE-2026-003',
          assetNo: 'AST-00142',
          problemList: ['แป้นพิมพ์ไม่ทำงาน'],
          imageList: [],
          remark: 'ปุ่ม Space bar กด 2 ครั้งถึงจะทำงาน',
          reporter: 'John Doe',
          created: DateTime.now().subtract(const Duration(days: 7)),
          currentStatus: 'Resolved',
          computerName: 'MacBook Pro',
        ),
      ];
}
