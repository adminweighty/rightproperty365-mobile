import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(RightPropertyApp(services: await bootstrap()));
}
