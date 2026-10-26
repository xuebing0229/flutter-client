import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('adventurersGuildStorageGet')
external JSString? _storageGet(JSString key);

@JS('adventurersGuildStorageSet')
external void _storageSet(JSString key, JSString value);

@JS('adventurersGuildStorageRemove')
external void _storageRemove(JSString key);

@JS('adventurersGuildDownloadBytes')
external void _downloadBytes(
  JSString fileName,
  JSString mimeType,
  JSString base64Data,
);

@JS('adventurersGuildPickImage')
external JSPromise<JSString> _pickImage();

@JS('adventurersGuildAssetRead')
external JSPromise<JSString> _assetRead(JSString key);

@JS('adventurersGuildAssetWrite')
external JSPromise<JSString> _assetWrite(JSString key, JSString base64Data);

@JS('adventurersGuildAssetDelete')
external JSPromise<JSString> _assetDelete(JSString key);

String? webStorageGet(String key) => _storageGet(key.toJS)?.toDart;

void webStorageSet(String key, String value) {
  _storageSet(key.toJS, value.toJS);
}

void webStorageRemove(String key) {
  _storageRemove(key.toJS);
}

void webDownloadBytes({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) {
  _downloadBytes(
    fileName.toJS,
    mimeType.toJS,
    base64Encode(bytes).toJS,
  );
}

class WebPickedImage {
  const WebPickedImage({
    required this.name,
    required this.bytes,
  });

  final String name;
  final Uint8List bytes;
}

Future<WebPickedImage?> webPickImage() async {
  final source = (await _pickImage().toDart).toDart;
  if (source.trim().isEmpty) return null;
  final decoded = jsonDecode(source);
  if (decoded is! Map ||
      decoded['name'] is! String ||
      decoded['data'] is! String) {
    throw const FormatException('浏览器返回的图片数据无效。');
  }
  return WebPickedImage(
    name: decoded['name'] as String,
    bytes: Uint8List.fromList(base64Decode(decoded['data'] as String)),
  );
}

Future<Uint8List?> webAssetRead(String key) async {
  final encoded = (await _assetRead(key.toJS).toDart).toDart;
  if (encoded.isEmpty) return null;
  return Uint8List.fromList(base64Decode(encoded));
}

Future<void> webAssetWrite(String key, Uint8List bytes) async {
  await _assetWrite(key.toJS, base64Encode(bytes).toJS).toDart;
}

Future<void> webAssetDelete(String key) async {
  await _assetDelete(key.toJS).toDart;
}
