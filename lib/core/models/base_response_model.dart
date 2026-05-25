class BaseResponseModel<T> {
  final int status;
  final String message;
  final T? entries;

  const BaseResponseModel({
    required this.status,
    required this.message,
    this.entries,
  });

  bool get isSuccess => status == 200;

  factory BaseResponseModel.fromJson(
    Map<String, dynamic> json,
    T? Function(dynamic) parseEntries,
  ) {
    return BaseResponseModel(
      status: json['status'] as int? ?? 0,
      message: json['message'] as String? ?? '',
      entries: parseEntries(json['entries']),
    );
  }
}
