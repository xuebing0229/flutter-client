import 'package:flutter/material.dart';

import 'app/app.dart' if (dart.library.html) 'app/app_web.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const App());
}
