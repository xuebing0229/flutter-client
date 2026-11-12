class LicenseHttpResponse {
  const LicenseHttpResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

class LicenseHttpTransportException implements Exception {
  const LicenseHttpTransportException(this.message, {required this.code});

  final String message;
  final String code;

  @override
  String toString() => message;
}
