import 'dart:convert';
import 'dart:io';

/// The few preferences that belong to the phone rather than to a farm or a
/// user's database: the language chosen before sign-in, large text, who is
/// signed in and the farm each user had open. One small JSON file, read once
/// at start so the first frame is already in the right language.
abstract interface class DeviceStore {
  Object? get(String key);

  /// Saves at once; a null value removes the key.
  Future<void> set(String key, Object? value);
}

/// For tests, and the stand-in until the file is open.
class MemoryDeviceStore implements DeviceStore {
  MemoryDeviceStore([Map<String, Object?>? values]) : values = {...?values};

  final Map<String, Object?> values;

  @override
  Object? get(String key) => values[key];

  @override
  Future<void> set(String key, Object? value) async {
    value == null ? values.remove(key) : values[key] = value;
  }
}

class FileDeviceStore implements DeviceStore {
  FileDeviceStore._(this._file, this._values);

  /// Reads `device.json` in [directory]; a missing or damaged file starts
  /// empty rather than stopping the app from opening.
  static Future<FileDeviceStore> open(Directory directory) async {
    final file = File('${directory.path}${Platform.pathSeparator}device.json');
    var values = <String, Object?>{};
    try {
      values = (jsonDecode(await file.readAsString()) as Map)
          .cast<String, Object?>();
    } on Object {
      // first run, or a file cut short: the defaults apply
    }
    return FileDeviceStore._(file, values);
  }

  final File _file;
  final Map<String, Object?> _values;
  Future<void> _writing = Future.value();

  @override
  Object? get(String key) => _values[key];

  @override
  Future<void> set(String key, Object? value) {
    value == null ? _values.remove(key) : _values[key] = value;
    final text = jsonEncode(_values);
    // one write at a time, through a temporary file, so a crash mid-write
    // never leaves half a file
    return _writing = _writing.then((_) async {
      final tmp = File('${_file.path}.tmp'); // gate: not user-facing
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(_file.path);
    });
  }
}
