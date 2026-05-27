import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:yanji/utils/config_loader.dart';

/// 进度回调：(已完成文件数, 总文件数, 当前文件名)
typedef ProgressCallback = void Function(int completed, int total, String currentFile);

class CloudStorageService {
  final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15)));

  // ==================== S3 (AWS Signature V4) ====================

  String _pad(int n) => n.toString().padLeft(2, '0');

  String _iso8601Basic(DateTime dt) {
    final u = dt.toUtc();
    return '${u.year}${_pad(u.month)}${_pad(u.day)}T${_pad(u.hour)}${_pad(u.minute)}${_pad(u.second)}Z';
  }

  String _dateOnly(DateTime dt) {
    final u = dt.toUtc();
    return '${u.year}${_pad(u.month)}${_pad(u.day)}';
  }

  /// 构建 AWS Signature V4 签名 headers
  Map<String, String> _signRequest({
    required String method,
    required String host,
    required String path,
    required S3Config config,
    DateTime? now,
    String? contentType,
    Uint8List? body,
  }) {
    final dt = now ?? DateTime.now().toUtc();
    final dateStamp = _dateOnly(dt);
    final amzDate = _iso8601Basic(dt);
    final region = config.region.isEmpty ? 'us-east-1' : config.region;

    final payloadHash = body != null
        ? sha256.convert(body).toString()
        : sha256.convert(utf8.encode('')).toString();

    final headers = <String, String>{
      'host': host,
      'x-amz-date': amzDate,
      'x-amz-content-sha256': payloadHash,
    };
    if (contentType != null) headers['content-type'] = contentType;

    // Signed headers
    final signedHeaderKeys = headers.keys.toList()..sort();
    final signedHeaders = signedHeaderKeys.join(';');

    // Canonical request
    final canonicalHeaders =
        signedHeaderKeys.map((k) => '$k:${headers[k]}\n').join();
    final canonicalRequest = [
      method.toUpperCase(),
      path,
      '', // query string
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');

    // String to sign
    final credentialScope = '$dateStamp/$region/s3/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      credentialScope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    // Signing key
    List<int> sign(List<int> key, String msg) {
      final hmac = Hmac(sha256, key);
      return hmac.convert(utf8.encode(msg)).bytes;
    }

    var kDate = sign(utf8.encode('AWS4${config.secretKey}'), dateStamp);
    var kRegion = sign(kDate, region);
    var kService = sign(kRegion, 's3');
    var kSigning = sign(kService, 'aws4_request');

    final signature = Hmac(sha256, kSigning)
        .convert(utf8.encode(stringToSign))
        .toString();

    headers['authorization'] =
        'AWS4-HMAC-SHA256 Credential=${config.accessKey}/$credentialScope, '
        'SignedHeaders=$signedHeaders, Signature=$signature';

    return headers;
  }

  String _s3Host(S3Config config) {
    if (config.usePathStyle) {
      // Path style: endpoint 本身就包含 host
      final uri = Uri.parse(config.endpoint);
      return uri.host;
    }
    // Virtual-hosted: bucket.endpoint
    final uri = Uri.parse(config.endpoint);
    return '${config.bucket}.${uri.host}';
  }

  String _s3Path(S3Config config, String objectKey) {
    final prefix = config.usePathStyle ? '/${config.bucket}' : '';
    return '$prefix/$objectKey';
  }

  /// 测试 S3 连接（HEAD 请求）
  Future<String> testS3Connection(S3Config config) async {
    if (!config.isConfigured) {
      throw Exception('S3 配置不完整，请检查 endpoint、bucket、accessKey');
    }

    final uri = Uri.parse(config.endpoint);
    final host = _s3Host(config);
    final path = _s3Path(config, '');

    final headers = _signRequest(
      method: 'GET',
      host: host,
      path: path,
      config: config,
    );

    final response = await _dio.get(
      config.usePathStyle
          ? '${config.endpoint}/?list-type=2&max-keys=1'
          : '${config.endpoint}/?list-type=2&max-keys=1'.replaceFirst(
              uri.host, host),
      options: Options(headers: headers),
    );

    if (response.statusCode == 200) {
      return 'S3 连接成功\nBucket: ${config.bucket}\nRegion: ${config.region}';
    }
    throw Exception('S3 连接失败: ${response.statusCode}');
  }

  /// 列出 S3 文件
  Future<List<String>> listS3Files(S3Config config) async {
    if (!config.isConfigured) throw Exception('S3 未配置');

    final host = _s3Host(config);
    final path = _s3Path(config, '');

    final headers = _signRequest(
      method: 'GET',
      host: host,
      path: path,
      config: config,
    );

    final endpoint = config.endpoint.endsWith('/')
        ? config.endpoint.substring(0, config.endpoint.length - 1)
        : config.endpoint;

    final response = await _dio.get(
      '$endpoint/?list-type=2&max-keys=100',
      options: Options(headers: headers),
    );

    if (response.statusCode == 200) {
      final body = response.data.toString();
      final keys = <String>[];
      final keyPattern = RegExp(r'<Key>(.*?)</Key>');
      for (final match in keyPattern.allMatches(body)) {
        keys.add(match.group(1)!);
      }
      return keys;
    }
    throw Exception('列出文件失败: ${response.statusCode}');
  }

  /// 上传文件到 S3
  Future<void> uploadToS3(String filePath, S3Config config) async {
    if (!config.isConfigured) throw Exception('S3 未配置');

    final file = File(filePath);
    if (!await file.exists()) throw Exception('文件不存在: $filePath');

    final fileBytes = await file.readAsBytes();
    final objectKey = filePath.split(Platform.pathSeparator).last;

    final host = _s3Host(config);
    final path = _s3Path(config, objectKey);

    final headers = _signRequest(
      method: 'PUT',
      host: host,
      path: path,
      config: config,
      contentType: 'application/octet-stream',
      body: fileBytes,
    );

    final endpoint = config.endpoint.endsWith('/')
        ? config.endpoint.substring(0, config.endpoint.length - 1)
        : config.endpoint;

    final uploadUrl = config.usePathStyle
        ? '$endpoint/$objectKey'
        : '$endpoint/$objectKey'.replaceFirst(Uri.parse(endpoint).host, host);

    await _dio.put(
      uploadUrl,
      data: Stream.fromIterable([fileBytes]),
      options: Options(
        headers: {
          ...headers,
          'content-type': 'application/octet-stream',
          'content-length': fileBytes.length,
        },
      ),
    );
  }

  // ==================== WebDAV ====================

  String _webdavAuthHeader(WebDAVConfig config) {
    final credentials = base64Encode(
        utf8.encode('${config.username}:${config.password}'));
    return 'Basic $credentials';
  }

  /// 测试 WebDAV 连接（PROPFIND）
  Future<String> testWebDAVConnection(WebDAVConfig config) async {
    if (!config.isConfigured) {
      throw Exception('WebDAV 配置不完整，请检查 URL 和用户名');
    }

    final url = config.url.endsWith('/') ? config.url : '${config.url}/';

    final response = await _dio.request(
      url,
      data: '''<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:">
  <D:allprop/>
</D:propfind>''',
      options: Options(
        method: 'PROPFIND',
        headers: {
          'Authorization': _webdavAuthHeader(config),
          'Depth': '0',
          'Content-Type': 'application/xml',
        },
      ),
    );

    if (response.statusCode == 207 || response.statusCode == 200) {
      return 'WebDAV 连接成功\n地址: ${config.url}\n用户: ${config.username}';
    }
    throw Exception('WebDAV 连接失败: ${response.statusCode}');
  }

  /// 列出 WebDAV 文件
  Future<List<String>> listWebDAVFiles(WebDAVConfig config) async {
    if (!config.isConfigured) throw Exception('WebDAV 未配置');

    final url = config.url.endsWith('/') ? config.url : '${config.url}/';

    final response = await _dio.request(
      url,
      data: '''<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:">
  <D:displayname/>
</D:propfind>''',
      options: Options(
        method: 'PROPFIND',
        headers: {
          'Authorization': _webdavAuthHeader(config),
          'Depth': '1',
          'Content-Type': 'application/xml',
        },
      ),
    );

    if (response.statusCode == 207 || response.statusCode == 200) {
      final body = response.data.toString();
      final files = <String>[];
      final hrefPattern = RegExp(r'<D:href>(.*?)</D:href>');
      for (final match in hrefPattern.allMatches(body)) {
        final href = match.group(1)!;
        // 跳过目录本身
        final name = Uri.decodeComponent(href).split('/').where((s) => s.isNotEmpty).last;
        if (name.isNotEmpty) files.add(name);
      }
      return files;
    }
    throw Exception('列出文件失败: ${response.statusCode}');
  }

  /// 上传文件到 WebDAV
  Future<void> uploadToWebDAV(String filePath, WebDAVConfig config) async {
    if (!config.isConfigured) throw Exception('WebDAV 未配置');

    final file = File(filePath);
    if (!await file.exists()) throw Exception('文件不存在: $filePath');

    final fileBytes = await file.readAsBytes();
    final fileName = filePath.split(Platform.pathSeparator).last;
    final uploadUrl = config.url.endsWith('/')
        ? '${config.url}$fileName'
        : '${config.url}/$fileName';

    final response = await _dio.put(
      uploadUrl,
      data: Stream.fromIterable([fileBytes]),
      options: Options(
        headers: {
          'Authorization': _webdavAuthHeader(config),
          'Content-Type': 'application/octet-stream',
          'Content-Length': fileBytes.length,
        },
      ),
    );

    if (response.statusCode != 201 && response.statusCode != 204) {
      throw Exception('上传失败: ${response.statusCode}');
    }
  }

  // ==================== 文件夹级导出/导入 ====================

  /// 导出会议文件夹到 S3
  Future<void> exportFolderToS3(
    String folderPath,
    String folderName,
    S3Config config, {
    ProgressCallback? onProgress,
  }) async {
    if (!config.isConfigured) throw Exception('S3 未配置');

    final dir = Directory(folderPath);
    if (!await dir.exists()) throw Exception('文件夹不存在: $folderPath');

    final files = await dir.list().where((e) => e is File).cast<File>().toList();
    final total = files.length;

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final fileName = file.path.split(Platform.pathSeparator).last;
      final objectKey = 'meetings/$folderName/$fileName';

      onProgress?.call(i, total, fileName);

      final fileBytes = await file.readAsBytes();
      final host = _s3Host(config);
      final path = _s3Path(config, objectKey);

      final headers = _signRequest(
        method: 'PUT',
        host: host,
        path: path,
        config: config,
        contentType: 'application/octet-stream',
        body: fileBytes,
      );

      final endpoint = config.endpoint.endsWith('/')
          ? config.endpoint.substring(0, config.endpoint.length - 1)
          : config.endpoint;

      final uploadUrl = config.usePathStyle
          ? '$endpoint/$objectKey'
          : '$endpoint/$objectKey'.replaceFirst(Uri.parse(endpoint).host, host);

      await _dio.put(
        uploadUrl,
        data: Stream.fromIterable([fileBytes]),
        options: Options(
          headers: {
            ...headers,
            'content-type': 'application/octet-stream',
            'content-length': fileBytes.length,
          },
        ),
      );
    }

    onProgress?.call(total, total, '');
  }

  /// 导出会议文件夹到 WebDAV
  Future<void> exportFolderToWebDAV(
    String folderPath,
    String folderName,
    WebDAVConfig config, {
    ProgressCallback? onProgress,
  }) async {
    if (!config.isConfigured) throw Exception('WebDAV 未配置');

    final dir = Directory(folderPath);
    if (!await dir.exists()) throw Exception('文件夹不存在: $folderPath');

    final files = await dir.list().where((e) => e is File).cast<File>().toList();
    final total = files.length;
    final baseUrl = config.url.endsWith('/')
        ? config.url.substring(0, config.url.length - 1)
        : config.url;

    // 创建子目录（WebDAV MKCOL）
    try {
      await _dio.request(
        '$baseUrl/meetings/$folderName/',
        data: '',
        options: Options(
          method: 'MKCOL',
          headers: {'Authorization': _webdavAuthHeader(config)},
        ),
      );
    } catch (_) {
      // 目录可能已存在，忽略错误
    }

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final fileName = file.path.split(Platform.pathSeparator).last;

      onProgress?.call(i, total, fileName);

      final fileBytes = await file.readAsBytes();
      final uploadUrl = '$baseUrl/meetings/$folderName/$fileName';

      final response = await _dio.put(
        uploadUrl,
        data: Stream.fromIterable([fileBytes]),
        options: Options(
          headers: {
            'Authorization': _webdavAuthHeader(config),
            'Content-Type': 'application/octet-stream',
            'Content-Length': fileBytes.length,
          },
        ),
      );

      if (response.statusCode != 201 && response.statusCode != 204) {
        throw Exception('上传 $fileName 失败: ${response.statusCode}');
      }
    }

    onProgress?.call(total, total, '');
  }

  /// 从 S3 导入会议文件夹
  Future<void> importFolderFromS3(
    String folderName,
    String localFolderPath,
    S3Config config, {
    ProgressCallback? onProgress,
  }) async {
    if (!config.isConfigured) throw Exception('S3 未配置');

    // 先列出该文件夹下所有文件
    final host = _s3Host(config);
    final prefix = 'meetings/$folderName/';
    final path = _s3Path(config, '');

    final headers = _signRequest(
      method: 'GET',
      host: host,
      path: path,
      config: config,
    );

    final endpoint = config.endpoint.endsWith('/')
        ? config.endpoint.substring(0, config.endpoint.length - 1)
        : config.endpoint;

    final response = await _dio.get(
      '$endpoint/?list-type=2&prefix=$prefix',
      options: Options(headers: headers),
    );

    if (response.statusCode != 200) {
      throw Exception('列出文件失败: ${response.statusCode}');
    }

    final body = response.data.toString();
    final keys = <String>[];
    final keyPattern = RegExp(r'<Key>(.*?)</Key>');
    for (final match in keyPattern.allMatches(body)) {
      keys.add(match.group(1)!);
    }

    final total = keys.length;
    final localDir = Directory(localFolderPath);
    if (!await localDir.exists()) {
      await localDir.create(recursive: true);
    }

    for (int i = 0; i < keys.length; i++) {
      final objectKey = keys[i];
      final fileName = objectKey.split('/').last;

      onProgress?.call(i, total, fileName);

      final getHeaders = _signRequest(
        method: 'GET',
        host: host,
        path: _s3Path(config, objectKey),
        config: config,
      );

      final downloadUrl = config.usePathStyle
          ? '$endpoint/$objectKey'
          : '$endpoint/$objectKey'.replaceFirst(Uri.parse(endpoint).host, host);

      final downloadResponse = await _dio.get(
        downloadUrl,
        options: Options(headers: getHeaders, responseType: ResponseType.bytes),
      );

      final fileBytes = Uint8List.fromList(downloadResponse.data);
      await File('$localFolderPath/$fileName').writeAsBytes(fileBytes);
    }

    onProgress?.call(total, total, '');
  }

  /// 从 WebDAV 导入会议文件夹
  Future<void> importFolderFromWebDAV(
    String folderName,
    String localFolderPath,
    WebDAVConfig config, {
    ProgressCallback? onProgress,
  }) async {
    if (!config.isConfigured) throw Exception('WebDAV 未配置');

    final baseUrl = config.url.endsWith('/')
        ? config.url.substring(0, config.url.length - 1)
        : config.url;

    // 列出子目录
    final response = await _dio.request(
      '$baseUrl/meetings/$folderName/',
      data: '''<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:">
  <D:displayname/>
</D:propfind>''',
      options: Options(
        method: 'PROPFIND',
        headers: {
          'Authorization': _webdavAuthHeader(config),
          'Depth': '1',
          'Content-Type': 'application/xml',
        },
      ),
    );

    if (response.statusCode != 207 && response.statusCode != 200) {
      throw Exception('列出文件失败: ${response.statusCode}');
    }

    final body = response.data.toString();
    final files = <String>[];
    final hrefPattern = RegExp(r'<D:href>(.*?)</D:href>');
    for (final match in hrefPattern.allMatches(body)) {
      final href = match.group(1)!;
      final name = Uri.decodeComponent(href).split('/').where((s) => s.isNotEmpty).last;
      if (name.isNotEmpty && !name.endsWith('/')) {
        files.add(name);
      }
    }

    final total = files.length;
    final localDir = Directory(localFolderPath);
    if (!await localDir.exists()) {
      await localDir.create(recursive: true);
    }

    for (int i = 0; i < files.length; i++) {
      final fileName = files[i];

      onProgress?.call(i, total, fileName);

      final downloadUrl = '$baseUrl/meetings/$folderName/$fileName';
      final downloadResponse = await _dio.get(
        downloadUrl,
        options: Options(
          headers: {'Authorization': _webdavAuthHeader(config)},
          responseType: ResponseType.bytes,
        ),
      );

      final fileBytes = Uint8List.fromList(downloadResponse.data);
      await File('$localFolderPath/$fileName').writeAsBytes(fileBytes);
    }

    onProgress?.call(total, total, '');
  }
}
