import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../controllers/sign_in_controller.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isSignUp = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final controller = ref.read(signInControllerProvider.notifier);
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final ok = _isSignUp
        ? await controller.signUp(email: email, password: password)
        : await controller.signIn(email: email, password: password);
    if (!mounted) return;
    if (ok) {
      context.go('/');
    }
  }

  bool get _showAppleButton {
    if (kIsWeb) return true; // Apple OAuth web sí soportado.
    return Platform.isIOS || Platform.isMacOS;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final state = ref.watch(signInControllerProvider);
    final controller = ref.read(signInControllerProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.26),
                      Theme.of(
                        context,
                      ).colorScheme.tertiary.withValues(alpha: 0.16),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(1.2),
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(23),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _AuthBadge(isSignUp: _isSignUp),
                          const SizedBox(height: 18),
                          Text(
                            _isSignUp ? t.authSignUpTitle : t.authSignInTitle,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 28),
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: InputDecoration(
                              labelText: t.authEmail,
                              prefixIcon: const Icon(Icons.mail_outline),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return t.errorGeneric;
                              }
                              if (!v.contains('@')) return t.errorGeneric;
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: true,
                            autofillHints: const [AutofillHints.password],
                            decoration: InputDecoration(
                              labelText: t.authPassword,
                              prefixIcon: const Icon(Icons.lock_outline),
                            ),
                            validator: (v) {
                              if (v == null || v.length < 6) {
                                return t.errorGeneric;
                              }
                              return null;
                            },
                          ),
                          if (state.errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              state.errorMessage!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: state.isSubmitting ? null : _submit,
                            child: state.isSubmitting
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(_isSignUp ? t.authSignUp : t.authSignIn),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Text(
                                  'o',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                              const Expanded(child: Divider()),
                            ],
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: state.isSubmitting
                                ? null
                                : controller.signInWithGoogle,
                            icon: const Icon(Icons.g_mobiledata, size: 28),
                            label: Text(t.authContinueWithGoogle),
                          ),
                          if (_showAppleButton) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: state.isSubmitting
                                  ? null
                                  : controller.signInWithApple,
                              icon: const Icon(Icons.apple, size: 24),
                              label: Text(t.authContinueWithApple),
                            ),
                          ],
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: () =>
                                setState(() => _isSignUp = !_isSignUp),
                            child: Text(
                              _isSignUp ? t.authHasAccount : t.authNoAccount,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthBadge extends StatelessWidget {
  const _AuthBadge({required this.isSignUp});

  final bool isSignUp;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.center,
      child: Container(
        width: 86,
        height: 86,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.primary.withValues(alpha: 0.12),
          border: Border.all(color: colors.primary.withValues(alpha: 0.45)),
          boxShadow: [
            BoxShadow(
              color: colors.primary.withValues(alpha: 0.18),
              blurRadius: 26,
            ),
          ],
        ),
        child: Icon(
          isSignUp ? Icons.auto_awesome : Icons.school,
          color: colors.primary,
          size: 42,
        ),
      ),
    );
  }
}
