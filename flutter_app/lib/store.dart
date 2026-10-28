import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'model.dart';

/// The one place data is read from and written to.
///
/// A later sync system (git-like merges over the local network, QR pairing)
/// wraps this class; nothing else in the app touches the file.
class Store {
  Store({this.folderName = 'CarBuySavings'});

  final String folderName;

  File? _file;
  Future<void> _queue = Future.value();

  Future<File> _dataFile() async {
    final dir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/$folderName',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return _file = File('${dir.path}/data.json');
  }

  /// Reads the stored file, seeding it from the bundled asset on first run.
  Future<SavingsData> load() async {
    final file = await _dataFile();
    if (!await file.exists()) {
      final seed = await _seed();
      if (seed != null) await file.writeAsString(seed);
    }
    try {
      return SavingsData.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } catch (_) {
      return SavingsData.defaults();
    }
  }

  /// The real data if it was bundled, otherwise the committed example; null
  /// when neither is present, which leaves the app on its defaults.
  Future<String?> _seed() async {
    for (final asset in const [
      'assets/seed_data.json',
      'assets/seed_data.example.json',
    ]) {
      try {
        return await rootBundle.loadString(asset);
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// Writes atomically (tmp + rename), and serializes writes so a burst of
  /// edits can never interleave.
  Future<void> save(SavingsData data) {
    final text = const JsonEncoder.withIndent('  ').convert(data.toJson());
    final next = _queue.then((_) async {
      final file = _file ?? await _dataFile();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(file.path);
    });
    // Keep the chain alive after a failed write, but let the caller see the error.
    _queue = next.catchError((_) {});
    return next;
  }

  /// Where the data lives, for the README and for troubleshooting.
  Future<String> path() async => (_file ?? await _dataFile()).path;
}
