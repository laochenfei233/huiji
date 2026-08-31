import 'package:path_provider/path_provider.dart';

Future<String> getDocsPath() async {
  final dir = await getApplicationDocumentsDirectory();
  return dir.path;
}

Future<String> getTempPath() async {
  final dir = await getTemporaryDirectory();
  return dir.path;
}
