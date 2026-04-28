import 'package:equatable/equatable.dart';

class AppUser extends Equatable {
  const AppUser({
    required this.id,
    required this.email,
    this.displayName,
    this.preferredLanguage = 'es',
  });

  final String id;
  final String email;
  final String? displayName;
  final String preferredLanguage;

  @override
  List<Object?> get props => [id, email, displayName, preferredLanguage];
}
