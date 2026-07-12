import 'package:diaspora_nearby/config/app_environment.dart';
import 'package:diaspora_nearby/main.dart' as app;

Future<void> main() {
  return app.runDiasporaApp(environment: AppEnvironment.production);
}
