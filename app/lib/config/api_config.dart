/// Where the app looks for the room booking API.
///
/// The host differs per target, which is why this is a build-time setting
/// rather than a constant compiled into every screen:
///
///   * iOS simulator / desktop   `http://localhost:3000`
///   * Android emulator          `http://10.0.2.2:3000`
///   * Physical device           your machine's LAN address, e.g. `http://192.168.1.20:3000`
///
/// Override it when running or building:
///
/// ```sh
/// flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
/// ```
class ApiConfig {
  const ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  /// Turns a path returned by the API into a URL this device can fetch.
  ///
  /// The server returns room images as relative paths such as
  /// `/uploads/room.jpg`, so that the host stays correct whether the app is
  /// running on an emulator, a simulator or a physical device. Absolute URLs
  /// are passed through untouched.
  static String resolveUrl(String pathOrUrl) {
    if (pathOrUrl.isEmpty) return '';
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return pathOrUrl;
    }
    final separator = pathOrUrl.startsWith('/') ? '' : '/';
    return '$baseUrl$separator$pathOrUrl';
  }
}
