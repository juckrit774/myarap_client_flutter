import 'package:dio/dio.dart';
import '../models/device_model.dart';

class HomeService {
  final Dio dio;

  HomeService(this.dio);

  Future<List<DeviceModel>> loadDevices() async {
    final response = await dio.get('/devices');

    final list = response.data as List;

    return list.map((e) => DeviceModel.fromJson(e)).toList();
  }
}