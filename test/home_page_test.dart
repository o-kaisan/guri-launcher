import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guri_launcher/application/home_role_service.dart';
import 'package:guri_launcher/domain/home_role_status.dart';
import 'package:guri_launcher/infrastructure/android_home_role_gateway.dart';
import 'package:guri_launcher/presentation/home_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('guri_launcher/home_role');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var isHome = false;
  var requests = 0;

  setUp(() {
    isHome = false;
    requests = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'isCurrentHome':
          return isHome;
        case 'requestHomeRole':
          requests++;
          return 'requestStarted';
        default:
          throw MissingPluginException();
      }
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets(
    'HOME is requested only on tap and selection refreshes on resume',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            service: HomeRoleService(const AndroidHomeRoleGateway()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests, 0);
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text('システム画面でホームアプリを選択してください'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      isHome = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(requests, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      isHome = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(requests, 1);
    },
  );

  test('unknown native result is treated as failure', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => 'unknown');
    expect(
      await const AndroidHomeRoleGateway().requestHomeRole(),
      HomeRoleStatus.failed,
    );
  });
}
