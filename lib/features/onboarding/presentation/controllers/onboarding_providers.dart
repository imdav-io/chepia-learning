import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingState {
  const OnboardingState({
    required this.isCompleted,
    required this.dailyReminderEnabled,
    this.selectedLevelCode,
  });

  final bool isCompleted;
  final bool dailyReminderEnabled;
  final String? selectedLevelCode;

  OnboardingState copyWith({
    bool? isCompleted,
    bool? dailyReminderEnabled,
    String? selectedLevelCode,
  }) {
    return OnboardingState(
      isCompleted: isCompleted ?? this.isCompleted,
      dailyReminderEnabled: dailyReminderEnabled ?? this.dailyReminderEnabled,
      selectedLevelCode: selectedLevelCode ?? this.selectedLevelCode,
    );
  }
}

class OnboardingPreferences {
  static const _completedKey = 'onboarding.completed';
  static const _selectedLevelKey = 'onboarding.selectedLevel';
  static const _dailyReminderKey = 'habits.dailyReminderEnabled';

  Future<OnboardingState> load() async {
    final prefs = await SharedPreferences.getInstance();
    return OnboardingState(
      isCompleted: prefs.getBool(_completedKey) ?? false,
      selectedLevelCode: prefs.getString(_selectedLevelKey),
      dailyReminderEnabled: prefs.getBool(_dailyReminderKey) ?? true,
    );
  }

  Future<void> complete({required String selectedLevelCode}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedKey, true);
    await prefs.setString(_selectedLevelKey, selectedLevelCode);
  }

  Future<void> setDailyReminderEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dailyReminderKey, enabled);
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_completedKey);
    await prefs.remove(_selectedLevelKey);
  }
}

final onboardingPreferencesProvider = Provider<OnboardingPreferences>((ref) {
  return OnboardingPreferences();
});

final onboardingStateProvider = FutureProvider<OnboardingState>((ref) {
  return ref.watch(onboardingPreferencesProvider).load();
});
