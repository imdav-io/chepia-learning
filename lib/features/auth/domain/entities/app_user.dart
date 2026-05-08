import 'package:equatable/equatable.dart';

class AppUser extends Equatable {
  const AppUser({
    required this.id,
    required this.email,
    this.displayName,
    this.fullName,
    this.givenName,
    this.familyName,
    this.avatarUrl,
    this.provider,
    this.locale,
    this.emailVerified = false,
    this.preferredLanguage = 'es',
  });

  final String id;
  final String email;
  final String? displayName;
  final String? fullName;
  final String? givenName;
  final String? familyName;
  final String? avatarUrl;
  final String? provider;
  final String? locale;
  final bool emailVerified;
  final String preferredLanguage;

  @override
  List<Object?> get props => [
    id,
    email,
    displayName,
    fullName,
    givenName,
    familyName,
    avatarUrl,
    provider,
    locale,
    emailVerified,
    preferredLanguage,
  ];
}
