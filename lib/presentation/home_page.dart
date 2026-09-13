import 'package:flutter/material.dart';

import '../application/home_role_service.dart';
import '../domain/home_role_status.dart';

class HomePage extends StatefulWidget {
  const HomePage({required this.service, super.key});
  final HomeRoleService service;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  HomeRoleStatus _status = HomeRoleStatus.notHome;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh(afterResume: true);
  }

  Future<void> _refresh({bool afterResume = false}) async {
    final currentStatus = await widget.service.currentStatus();
    if (!mounted) return;
    setState(() {
      _status = afterResume
          ? statusAfterResume(
              previous: _status,
              isCurrentHome: currentStatus == HomeRoleStatus.alreadyHome,
            )
          : currentStatus;
    });
  }

  Future<void> _requestHomeRole() async {
    final status = await widget.service.request();
    if (mounted) setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('guri-launcher'),
          const SizedBox(height: 12),
          Text(_message(_status)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _status == HomeRoleStatus.alreadyHome
                ? null
                : _requestHomeRole,
            child: const Text('デフォルトのホームに設定'),
          ),
        ],
      ),
    ),
  );
}

String _message(HomeRoleStatus status) => switch (status) {
  HomeRoleStatus.notHome || HomeRoleStatus.denied => 'デフォルトのホームに設定されていません',
  HomeRoleStatus.alreadyHome => 'デフォルトのホームに設定済みです',
  HomeRoleStatus.requestStarted ||
  HomeRoleStatus.settingsOpened => 'システム画面でホームアプリを選択してください',
  HomeRoleStatus.unavailable => 'この端末ではホームアプリを変更できません',
  HomeRoleStatus.failed => 'ホーム設定画面を開けませんでした',
};
