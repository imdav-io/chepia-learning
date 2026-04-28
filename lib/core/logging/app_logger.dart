import 'dart:developer' as developer;

import '../config/env.dart';

class AppLogger {
  AppLogger._();

  static void debug(String message, [Object? error, StackTrace? stackTrace]) {
    if (!Env.isDevelopment) return;
    developer.log(message, name: 'DEBUG', error: error, stackTrace: stackTrace);
  }

  static void info(String message) {
    developer.log(message, name: 'INFO');
  }

  static void warn(String message, [Object? error, StackTrace? stackTrace]) {
    developer.log(message, name: 'WARN', error: error, stackTrace: stackTrace);
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    developer.log(message, name: 'ERROR', error: error, stackTrace: stackTrace);
  }
}
