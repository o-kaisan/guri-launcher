import 'package:flutter_test/flutter_test.dart';
import 'package:guri_launcher/domain/home_role_status.dart';

void main() {
  test('current home becomes already home after resume', () {
    expect(
      statusAfterResume(
        previous: HomeRoleStatus.settingsOpened,
        isCurrentHome: true,
      ),
      HomeRoleStatus.alreadyHome,
    );
  });
  test('returning from a request without selection becomes denied', () {
    expect(
      statusAfterResume(
        previous: HomeRoleStatus.requestStarted,
        isCurrentHome: false,
      ),
      HomeRoleStatus.denied,
    );
  });
  test('platform failures survive resume', () {
    expect(
      statusAfterResume(previous: HomeRoleStatus.failed, isCurrentHome: false),
      HomeRoleStatus.failed,
    );
  });
}
