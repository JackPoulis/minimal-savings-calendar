import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:savings/model.dart';
import 'package:savings/store.dart';

/// Points the store at a throwaway directory instead of real Documents.
class _TempPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TempPathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Store store;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('savings_store_test');
    PathProviderPlatform.instance = _TempPathProvider(temp.path);
    store = Store();
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('seeds from the bundled asset on first run', () async {
    final data = await store.load();
    final file = File(await store.path());

    expect(file.existsSync(), isTrue);
    final onDisk =
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(onDisk.keys, containsAll(['startDate', 'endDate', 'entries']));
    expect(data.entries.length, (onDisk['entries'] as List).length);
  });

  test('saves and reads back the same data', () async {
    final data = (await store.load()).copyWith(
      goal: 4321,
      entries: [
        const Entry(
          id: 'x',
          type: 'out',
          title: 'Tyres',
          amount: 250.5,
          date: '2026-10-01',
        ),
      ],
    );
    await store.save(data);

    final again = await Store().load();
    expect(again.goal, 4321);
    expect(again.entries.single.title, 'Tyres');
    expect(again.entries.single.amount, 250.5);
    expect(again.entries.single.type, 'out');
  });

  test('leaves no temp file behind and keeps the JSON indented', () async {
    await store.save(await store.load());
    final files = temp
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.split(Platform.pathSeparator).last)
        .toList();

    expect(files, ['data.json']);
    expect(File(await store.path()).readAsStringSync(), startsWith('{\n  "'));
  });

  test('concurrent saves all land, last one wins', () async {
    final base = await store.load();
    await Future.wait([
      for (var i = 1; i <= 5; i++) store.save(base.copyWith(goal: i * 100)),
    ]);

    expect((await Store().load()).goal, 500);
  });
}
