/// Thrown when the Django auth API rejects or misformats a request.
class AuthApiException implements Exception {
  AuthApiException(this.message, {this.statusCode, this.isInvalidCredentials = false});

  final String message;
  final int? statusCode;
  final bool isInvalidCredentials;

  @override
  String toString() => message;
}
