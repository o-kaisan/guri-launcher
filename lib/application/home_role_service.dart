import '../domain/home_role_status.dart';

abstract interface class HomeRoleGateway {
  Future<bool> isCurrentHome();
  Future<HomeRoleStatus> requestHomeRole();
}

class HomeRoleService {
  HomeRoleService(this._gateway);
  final HomeRoleGateway _gateway;

  Future<HomeRoleStatus> currentStatus() async => await _gateway.isCurrentHome()
      ? HomeRoleStatus.alreadyHome
      : HomeRoleStatus.notHome;
  Future<HomeRoleStatus> request() => _gateway.requestHomeRole();
}
