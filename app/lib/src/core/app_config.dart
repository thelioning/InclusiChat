class AppConfig {
  static const String appName = 'InclusiChat';
  static const String version = '1.4.4';
  static const int buildNumber = 37;
  static const String releaseType = 'Release Estable';
  static const String authorName = 'Ermógenes Rodríguez Fernández';
  static const String organization = 'Baremetal Academy';

  static String get fullVersionString =>
      'Versión $version (Build $buildNumber) • $releaseType';

  static String get shortVersionString => 'v$version';

  static String get footerCredit =>
      '$appName $shortVersionString • Hecho con 💜 por $authorName & $organization';

  static String get downloadUrl =>
      'https://github.com/thelioning/InclusiChat/releases/download/v$version/InclusiChat-v$version.apk';
}
