import 'package:easy_dice_thrower/data/tray_store.dart';

class MemoryStore implements TrayStore {
  MemoryStore([this.value]);

  String? value;
  bool failWrites = false;
  final List<String> writes = [];

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    if (failWrites) throw StateError('Storage unavailable');
    writes.add(value);
    this.value = value;
  }
}
