import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/tray_orientation.dart';

typedef OrientationRequest = Future<void> Function(TrayOrientation orientation);

class OrientationLock extends ChangeNotifier {
  OrientationLock({bool? supported, OrientationRequest? request})
    : supported =
          supported ??
          (!kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.android ||
                  defaultTargetPlatform == TargetPlatform.iOS)),
      _request = request ?? _requestPlatform;

  final bool supported;
  final OrientationRequest _request;
  Future<void> _tail = Future.value();
  TrayOrientation? _requested;
  int _revision = 0;
  bool _failed = false;
  bool _disposed = false;

  bool get failed => _failed;
  Future<void> get settled => _tail;

  void apply(TrayOrientation orientation, {bool retry = false}) {
    if (_disposed || !supported || (!retry && _requested == orientation)) {
      return;
    }
    _requested = orientation;
    final revision = ++_revision;
    _failed = false;
    notifyListeners();
    _tail = _tail.then((_) async {
      if (_disposed || revision != _revision) return;
      try {
        await _request(orientation);
      } catch (_) {
        if (!_disposed && revision == _revision) {
          _failed = true;
          notifyListeners();
        }
      }
    });
  }

  static Future<void> _requestPlatform(TrayOrientation orientation) {
    return SystemChrome.setPreferredOrientations([
      switch (orientation) {
        TrayOrientation.portrait => DeviceOrientation.portraitUp,
        TrayOrientation.landscape => DeviceOrientation.landscapeLeft,
      },
    ]);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
