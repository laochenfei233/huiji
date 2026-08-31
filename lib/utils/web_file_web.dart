import 'dart:html' as html;

Future<void> downloadFile(String content, String fileName, {String mimeType = 'text/plain'}) async {
  final bytes = Uri.encodeFull(content);
  final dataUrl = 'data:$mimeType;charset=utf-8,$bytes';

  final anchor = html.AnchorElement(href: dataUrl)
    ..setAttribute('download', fileName)
    ..style.display = 'none';

  html.document.body!.children.add(anchor);
  anchor.click();
  anchor.remove();
}

Future<void> downloadBytes(List<int> bytes, String fileName, {String mimeType = 'application/octet-stream'}) async {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..style.display = 'none';

  html.document.body!.children.add(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}

Future<String?> pickFile({List<String>? acceptedExtensions}) async {
  final input = html.FileUploadInputElement()
    ..accept = acceptedExtensions?.join(',') ?? '*/*';

  input.click();

  final changeEvent = await input.onChange.first;
  if (changeEvent == null || input.files == null || input.files!.isEmpty) {
    return null;
  }

  final file = input.files!.first;
  final reader = html.FileReader();
  reader.readAsText(file);

  await reader.onLoad.first;
  return reader.result as String?;
}

Future<List<int>?> pickFileBytes({List<String>? acceptedExtensions}) async {
  final input = html.FileUploadInputElement()
    ..accept = acceptedExtensions?.join(',') ?? '*/*';

  input.click();

  final changeEvent = await input.onChange.first;
  if (changeEvent == null || input.files == null || input.files!.isEmpty) {
    return null;
  }

  final file = input.files!.first;
  final reader = html.FileReader();
  reader.readAsArrayBuffer(file);

  await reader.onLoad.first;
  return (reader.result as dynamic).toList().cast<int>();
}
