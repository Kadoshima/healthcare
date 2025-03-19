// lib/services/azure_storage_service.dart の修正

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;

/// Azureストレージサービスクラス
/// BlobストレージへのファイルアップロードなどAzureとの連携機能を提供
class AzureStorageService {
  // Azure Blob Storageの設定
  final String accountName;
  final String accountKey;
  final String containerName;

  // 状態管理
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _lastError = '';

  // 公開プロパティ
  bool get isUploading => _isUploading;
  double get uploadProgress => _uploadProgress;
  String get lastError => _lastError;

  // コンストラクタ - デフォルト値を設定
  AzureStorageService(
      {this.accountName = '', this.accountKey = '', this.containerName = ''});

  // 初期化メソッド (必要に応じて設定をロード)
  Future<bool> initialize() async {
    try {
      // アカウント情報が空の場合、モックモードで動作
      if (accountName.isEmpty || accountKey.isEmpty || containerName.isEmpty) {
        print('Azure Storage credentials not provided, running in mock mode');
        return true;
      }
      return true;
    } catch (e) {
      _lastError = 'Azure Storage initialization error: $e';
      print(_lastError);
      return false;
    }
  }

  /// ファイルアップロードメソッド
  /// 指定されたファイルパスのファイルをAzure Blob Storageにアップロード
  Future<bool> uploadFile(String filePath,
      {String? blobName, Function(double)? progressCallback}) async {
    // アカウント情報が未設定の場合は処理をスキップ
    if (accountName.isEmpty || accountKey.isEmpty || containerName.isEmpty) {
      print('Azure Storage is in mock mode, file upload simulated');
      _isUploading = true;
      _uploadProgress = 0.0;

      // アップロード進捗をシミュレート
      for (var i = 0; i <= 10; i++) {
        await Future.delayed(Duration(milliseconds: 100));
        _uploadProgress = i / 10;
        progressCallback?.call(_uploadProgress);
      }

      _isUploading = false;
      return true;
    }

    try {
      _isUploading = true;
      _uploadProgress = 0.0;
      _lastError = '';

      final file = File(filePath);
      if (!await file.exists()) {
        _lastError = 'ファイルが存在しません: $filePath';
        _isUploading = false;
        return false;
      }

      // ファイル名が指定されていない場合は元のファイル名を使用
      final fileName = blobName ?? path.basename(filePath);

      // 現在日時を含むブロブ名（被験者ID/日付/ファイル名）
      final date = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fullBlobName = 'experiments/$date/$fileName';

      // アップロード用のURLと認証ヘッダーを生成
      final url = Uri.parse(
          'https://$accountName.blob.core.windows.net/$containerName/$fullBlobName');
      final headers = _generateAuthorizationHeaders(fullBlobName);

      // ファイルデータの読み込み
      final bytes = await file.readAsBytes();

      // HTTPリクエストでアップロード
      final response = await http.put(
        url,
        headers: headers,
        body: bytes,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _uploadProgress = 1.0;
        progressCallback?.call(1.0);
        _isUploading = false;
        return true;
      } else {
        _lastError = 'アップロード失敗: ${response.statusCode} - ${response.body}';
        _isUploading = false;
        return false;
      }
    } catch (e) {
      _lastError = 'アップロードエラー: $e';
      _isUploading = false;
      return false;
    }
  }

  /// 複数ファイルのアップロード
  Future<bool> uploadFiles(List<String> filePaths,
      {String? prefix, Function(double)? progressCallback}) async {
    // アカウント情報が未設定の場合は処理をスキップ
    if (accountName.isEmpty || accountKey.isEmpty || containerName.isEmpty) {
      print('Azure Storage is in mock mode, file uploads simulated');
      _isUploading = true;
      _uploadProgress = 0.0;

      // アップロード進捗をシミュレート
      for (var i = 0; i <= 10; i++) {
        await Future.delayed(Duration(milliseconds: 100));
        _uploadProgress = i / 10;
        progressCallback?.call(_uploadProgress);
      }

      _isUploading = false;
      return true;
    }

    try {
      _isUploading = true;
      _uploadProgress = 0.0;
      _lastError = '';

      // 全体の進捗状況を計算するための変数
      int totalFiles = filePaths.length;
      int completedFiles = 0;

      for (final filePath in filePaths) {
        final fileName = path.basename(filePath);
        final result = await uploadFile(filePath,
            blobName: prefix != null ? '$prefix/$fileName' : fileName,
            progressCallback: (progress) {
          // 個別ファイルの進捗を全体に反映
          _uploadProgress = (completedFiles + progress) / totalFiles;
          progressCallback?.call(_uploadProgress);
        });

        if (!result) {
          _isUploading = false;
          return false;
        }

        completedFiles++;
        _uploadProgress = completedFiles / totalFiles;
        progressCallback?.call(_uploadProgress);
      }

      _isUploading = false;
      return true;
    } catch (e) {
      _lastError = '複数ファイルアップロードエラー: $e';
      _isUploading = false;
      return false;
    }
  }

  /// セッションデータのアップロード
  /// 指定されたセッションIDのデータファイルをすべてアップロード
  Future<bool> uploadSessionData(int sessionId, String exportPath,
      {String? subjectId, Function(double)? progressCallback}) async {
    try {
      final directory = Directory(exportPath);
      if (!await directory.exists()) {
        _lastError = 'エクスポートディレクトリが存在しません: $exportPath';
        return false;
      }

      // セッションに関連するファイルを検索
      final files = await directory
          .list()
          .where((entity) =>
              entity is File &&
              entity.path.contains('session_$sessionId') &&
              (entity.path.endsWith('.csv') || entity.path.endsWith('.json')))
          .map((entity) => entity.path)
          .toList();

      if (files.isEmpty) {
        _lastError = 'アップロードするファイルが見つかりません';
        return false;
      }

      // 被験者IDとセッションIDを含むプレフィックスを作成
      final prefix = subjectId != null
          ? 'subject_$subjectId/session_$sessionId'
          : 'session_$sessionId';

      // ファイルをアップロード
      return await uploadFiles(files,
          prefix: prefix, progressCallback: progressCallback);
    } catch (e) {
      _lastError = 'セッションデータアップロードエラー: $e';
      return false;
    }
  }

  /// Azureストレージ認証用のヘッダーを生成
  Map<String, String> _generateAuthorizationHeaders(String blobName) {
    // アカウント情報が未設定の場合は空のヘッダーを返す
    if (accountName.isEmpty || accountKey.isEmpty) {
      return {};
    }

    // 現在時刻（RFC 1123形式）
    final now = DateTime.now().toUtc();
    final formatter = DateFormat('EEE, dd MMM yyyy HH:mm:ss', 'en_US');
    final dateString = '${formatter.format(now)} GMT';

    // コンテンツタイプの設定
    final contentType = 'application/octet-stream';

    // 署名に使用する文字列を構築
    final stringToSign =
        'PUT\n\n\n\n\n$contentType\n\n\n\n\n\n\nx-ms-blob-type:BlockBlob\nx-ms-date:$dateString\nx-ms-version:2020-04-08\n/$accountName/$containerName/$blobName';

    // HMACで署名を計算
    final key = base64.decode(accountKey);
    final hmacSha256 = Hmac(sha256, key);
    final signature = hmacSha256.convert(utf8.encode(stringToSign));
    final authorizationHeader =
        'SharedKey $accountName:${base64.encode(signature.bytes)}';

    // ヘッダー情報を返す
    return {
      'Authorization': authorizationHeader,
      'x-ms-date': dateString,
      'x-ms-version': '2020-04-08',
      'x-ms-blob-type': 'BlockBlob',
      'Content-Type': contentType,
    };
  }
}
