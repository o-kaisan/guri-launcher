import 'package:flutter/services.dart';

import '../application/home_role_service.dart';
import '../domain/home_role_status.dart';

class AndroidHomeRoleGateway implements HomeRoleGateway {
  const AndroidHomeRoleGateway({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('guri_launcher/home_role');
  final MethodChannel _channel;

  @override
  Future<bool> isCurrentHome() async =>
      await _channel.invokeMethod<bool>('isCurrentHome') ?? false;

  @override
  Future<HomeRoleStatus> requestHomeRole() async {
    final value = await _channel.invokeMethod<String>('requestHomeRole');
    return HomeRoleStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => HomeRoleStatus.failed,
    );
  }
}
