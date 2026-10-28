import 'package:flutter/material.dart';

import 'app_page.dart';
import 'store.dart';
import 'sync/repository.dart';
import 'sync/role.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(SavingsApp(store: Store()));
}

class SavingsApp extends StatelessWidget {
  SavingsApp({super.key, required Store store, SyncRole? role})
    : role = role ?? platformRole(),
      repo = SyncRepository(
        store: store,
        isHub: (role ?? platformRole()).isHub,
      );

  /// The hub on Windows, a client on the phone. The role decides whether a
  /// write bumps the hub revision or marks fields dirty, so it is settled
  /// once, here.
  final SyncRole role;
  final SyncRepository repo;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Savings',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: DefaultTextStyle(
      style: body,
      child: AppPage(repo: repo, role: role),
    ),
  );
}
