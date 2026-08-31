import 'dart:typed_data';
export 'platform_web.dart' show Platform;

class File extends FileSystemEntity {
  File(String path) : super(path);

  Future<bool> exists() async => false;
  bool existsSync() => false;
  Future<String> readAsString() async => '';
  Future<File> writeAsString(String contents, {dynamic mode}) async => this;
  Future<File> writeAsBytes(List<int> bytes, {dynamic mode}) async => this;
  Future<Uint8List> readAsBytes() async => Uint8List(0);
  IOSink openWrite({dynamic mode}) => IOSink();
  Future<void> create({bool recursive = false}) async {}
  Future<File> delete() async => this;
}

class IOSink {
  void add(List<int> data) {}
  Future<void> flush() async {}
  Future<void> close() async {}
}

class Directory extends FileSystemEntity {
  Directory(String path) : super(path);

  Future<bool> exists() async => false;
  bool existsSync() => false;
  Future<Directory> create({bool recursive = false}) async => this;
  List<FileSystemEntity> listSync({bool recursive = false}) => [];
  Stream<FileSystemEntity> list({bool recursive = false}) async* {}
  Directory get parent => Directory(path);
  Future<void> delete({bool recursive = false}) async {}
}

class FileSystemEntity {
  final String path;
  FileSystemEntity(this.path);
  Future<int> length() async => 0;
  int lengthSync() => 0;
}

enum FileMode { append, write, read, writeOnly, writeOnlyAppend }
