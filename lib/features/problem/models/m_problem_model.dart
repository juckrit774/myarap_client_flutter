class MProblemModel {
  final String id;
  final String name;
  final bool requireRemark;
  bool isSelected;

  MProblemModel({
    required this.id,
    required this.name,
    this.requireRemark = false,
    this.isSelected = false,
  });

  factory MProblemModel.fromJson(Map<String, dynamic> json) {
    return MProblemModel(
      id: json['uniqueId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      requireRemark: json['requireRemark'] as bool? ?? false,
    );
  }

  void toggle() => isSelected = !isSelected;

  static List<MProblemModel> mockList() => [
        MProblemModel(id: 'p1', name: 'หน้าจอมีปัญหา', requireRemark: false),
        MProblemModel(id: 'p2', name: 'แป้นพิมพ์ไม่ทำงาน', requireRemark: false),
        MProblemModel(id: 'p3', name: 'แบตเตอรี่เสื่อม', requireRemark: true),
        MProblemModel(id: 'p4', name: 'Wi-Fi เชื่อมต่อไม่ได้', requireRemark: false),
        MProblemModel(id: 'p5', name: 'เครื่องร้อนผิดปกติ', requireRemark: true),
        MProblemModel(id: 'p6', name: 'เครื่องเปิดไม่ติด', requireRemark: false),
        MProblemModel(id: 'p7', name: 'ระบบเสียงผิดปกติ', requireRemark: false),
        MProblemModel(id: 'p8', name: 'อื่น ๆ', requireRemark: true),
      ];
}
