Future<void> downloadFile(String content, String fileName, {String mimeType = 'text/plain'}) async {
  // Native: use share_plus to share a temp file
  // This is a fallback - native platforms use the existing export flow
  throw UnsupportedError('Native 平台使用系统导出功能');
}

Future<String?> pickFile({List<String>? acceptedExtensions}) async {
  // Native: use file_picker package
  throw UnsupportedError('Native 平台使用系统文件选择器');
}
