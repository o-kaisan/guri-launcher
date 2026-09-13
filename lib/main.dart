import 'package:flutter/material.dart';

import 'application/home_role_service.dart';
import 'infrastructure/android_home_role_gateway.dart';
import 'presentation/home_page.dart';

void main() => runApp(const GuriLauncherApp());

class GuriLauncherApp extends StatelessWidget {
  const GuriLauncherApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'guri-launcher',
    theme: ThemeData(colorSchemeSeed: Colors.deepPurple),
    home: HomePage(service: HomeRoleService(const AndroidHomeRoleGateway())),
  );
}
