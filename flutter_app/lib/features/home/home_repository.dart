import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/api/dio_client.dart';
import 'models.dart';

final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  return HomeRepository(ref.watch(dioProvider));
});

class HomeRepository {
  HomeRepository(Dio dio) : _dio = dio;

  final Dio _dio;

  Future<MobileHome> fetchHome() async {
    try {
      final response = await _dio.get('/mobile/home/');
      return MobileHome.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  Future<void> clockIn({required bool sendLocation}) async {
    await _punch('/attendance/clock-in/', sendLocation: sendLocation);
  }

  Future<void> clockOut({required bool sendLocation}) async {
    await _punch('/attendance/clock-out/', sendLocation: sendLocation);
  }

  Future<void> _punch(String path, {required bool sendLocation}) async {
    Map<String, dynamic> body = {};
    if (sendLocation) {
      body = await _currentLocationBody();
    }
    try {
      await _dio.post(path, data: body);
    } on DioException catch (e) {
      throwApi(e);
    }
  }

  Future<Map<String, dynamic>> _currentLocationBody() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission is required for check-in at this company.');
    }

    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw Exception('Please enable GPS to check in.');
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return {
      'latitude': position.latitude,
      'longitude': position.longitude,
    };
  }
}
