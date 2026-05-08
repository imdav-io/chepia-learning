import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/config/env.dart';
import 'core/logging/app_logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  Object? supabaseInitError;
  try {
    Env.assertConfigured();
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
      debug: Env.isDevelopment,
    );
  } catch (e, st) {
    AppLogger.error('Supabase init failed', e, st);
    supabaseInitError = e;
  }

  await Hive.initFlutter();

  // Background audio solo en plataformas nativas. En web no aplica.
  if (!kIsWeb) {
    try {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'io.imdav.chepia.learning.channel.audio',
        androidNotificationChannelName: 'Lesson audio',
        androidNotificationOngoing: true,
      );
    } catch (e, st) {
      AppLogger.warn('JustAudioBackground init skipped', e, st);
    }
  }

  runApp(ProviderScope(child: ChepiaApp(supabaseInitError: supabaseInitError)));
}
