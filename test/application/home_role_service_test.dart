import 'package:flutter_test/flutter_test.dart';
import 'package:guri_launcher/application/home_role_service.dart';
import 'package:guri_launcher/domain/home_role_status.dart';

void main() {
  test('current status reflects the platform home selection', () async {
    expect(
      await HomeRoleService(_FakeGateway(isCurrent: true)).currentStatus(),
      HomeRoleStatus.alreadyHome,
    );
  });
  test('request result is returned from the platform gateway', () async {
    expect(
      await HomeRoleService(
        _FakeGateway(requestResult: HomeRoleStatus.requestStarted),
      ).request(),
      HomeRoleStatus.requestStarted,
    );
  });
}

class _FakeGateway implements HomeRoleGateway {
  _FakeGateway({
    this.isCurrent = false,
    this.requestResult = HomeRoleStatus.failed,
  });
  final bool isCurrent;
  final HomeRoleStatus requestResult;
  @override
  Future<bool> isCurrentHome() async => isCurrent;
  @override
  Future<HomeRoleStatus> requestHomeRole() async => requestResult;
}
