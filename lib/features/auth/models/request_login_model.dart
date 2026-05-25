class RequestLoginModel {
  final String computerName;
  final String serialNumber;
  final String macAddress;
  final String osVersion;
  final String appVersion;

  const RequestLoginModel({
    required this.computerName,
    required this.serialNumber,
    required this.macAddress,
    required this.osVersion,
    required this.appVersion,
  });

  Map<String, dynamic> toJson() => {
        'computerName': computerName,
        'serialNumber': serialNumber,
        'macAddress': macAddress,
        'osVersion': osVersion,
        'appVersion': appVersion,
      };
}
