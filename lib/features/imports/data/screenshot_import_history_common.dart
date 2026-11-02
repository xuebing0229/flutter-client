import 'package:cryptography/cryptography.dart';

String screenshotCardFingerprint({
  required String imageSha256,
  required int cardIndex,
  required bool products,
}) =>
    '${products ? 'products' : 'orders'}|$imageSha256|$cardIndex';

Future<String> hashScreenshotBytes(List<int> bytes) async {
  final hash = await Sha256().hash(bytes);
  return hash.bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
}

Set<String> mergeScreenshotImportFingerprints(
  Iterable<String> current,
  Iterable<String> incoming,
) {
  return <String>{
    ...current.where((item) => item.isNotEmpty),
    ...incoming.where((item) => item.isNotEmpty),
  };
}
