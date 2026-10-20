import 'package:flutter/foundation.dart';

/// Browser compatibility surface used by the shared 182 focus panel.
/// PWA has no Windows desktop-pet process, so no current-order binding exists.
class DesktopPetSettings extends ChangeNotifier {
  String? get currentOrderId => null;

  Future<void> refresh() async {}
}
