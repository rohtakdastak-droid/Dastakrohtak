import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';

class AuthScreen extends ConsumerStatefulWidget {
  final bool recovery;
  const AuthScreen({this.recovery = false, super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final email = TextEditingController(),
      password = TextEditingController(),
      displayName = TextEditingController(),
      phone = TextEditingController();
  final form = GlobalKey<FormState>();
  bool signup = false;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    displayName.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) {
      throw StateError('Fill all required fields');
    }
    final repo = ref.read(repositoryProvider);
    final auth = repo.client.auth;
    if (widget.recovery) {
      await auth.updateUser(UserAttributes(password: password.text));
    } else if (signup) {
      final result = await auth.signUp(
          email: email.text.trim(),
          password: password.text,
          data: {
            'display_name': displayName.text.trim(),
            'phone': phone.text.trim()
          },
          emailRedirectTo: 'com.dastak.app://auth/callback');
      if (result.session == null) {
        if (mounted) {
          toast(context,
              'Check your email to confirm your account, then sign in.');
        }
        return;
      }
      // Make sure the customer profile row carries name and phone.
      try {
        await repo.client.from('profiles').upsert({
          'id': result.user?.id,
          'display_name': displayName.text.trim(),
          'phone': phone.text.trim(),
          'role': 'customer'
        });
      } catch (_) {}
    } else {
      await auth.signInWithPassword(
          email: email.text.trim(), password: password.text);
    }
    ref.invalidate(accountProvider);
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
          child: Center(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Form(
                          key: form,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Icon(Icons.doorbell_rounded,
                                    size: 64, color: Color(0xFF0EA5E9)),
                                const SizedBox(height: 20),
                                Text(
                                    widget.recovery
                                        ? 'Set a new password'
                                        : 'A little closer.\nA lot more local.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineLarge),
                                const SizedBox(height: 12),
                                Text(widget.recovery
                                    ? 'Choose a strong password.'
                                    : 'Welcome to Dastak. Your neighbourhood, delivered.'),
                                const SizedBox(height: 24),
                                if (!widget.recovery) ...[
                                  if (signup) ...[
                                    TextFormField(
                                        controller: displayName,
                                        decoration: const InputDecoration(
                                            labelText: 'Your name'),
                                        validator: (v) =>
                                            (v?.trim().length ?? 0) >= 2
                                                ? null
                                                : 'Enter your name'),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                        controller: phone,
                                        keyboardType: TextInputType.phone,
                                        autofillHints: const [
                                          AutofillHints.telephoneNumber
                                        ],
                                        decoration: const InputDecoration(
                                            labelText: 'Phone number',
                                            prefixText: '+91 '),
                                        validator: (v) => RegExp(r'^\d{10}$')
                                                .hasMatch(
                                                    (v ?? '').replaceAll(RegExp(r'\D'), ''))
                                            ? null
                                            : 'Enter a 10-digit phone number'),
                                    const SizedBox(height: 12),
                                  ],
                                  TextFormField(
                                      controller: email,
                                      keyboardType: TextInputType.emailAddress,
                                      autofillHints: const [
                                        AutofillHints.email
                                      ],
                                      decoration: const InputDecoration(
                                          labelText: 'Email'),
                                      validator: (v) =>
                                          RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                                  .hasMatch(v ?? '')
                                              ? null
                                              : 'Enter a valid email')
                                ],
                                const SizedBox(height: 16),
                                TextFormField(
                                    controller: password,
                                    obscureText: true,
                                    decoration: const InputDecoration(
                                        labelText: 'Password'),
                                    validator: (v) => (v?.length ?? 0) >= 8
                                        ? null
                                        : 'Use at least 8 characters'),
                                const SizedBox(height: 24),
                                ActionButton(
                                    widget.recovery
                                        ? 'Update password'
                                        : signup
                                            ? 'Create account'
                                            : 'Sign in',
                                    submit),
                                if (!widget.recovery) ...[
                                  TextButton(
                                      onPressed: () =>
                                          setState(() => signup = !signup),
                                      child: Text(signup
                                          ? 'Already have an account? Sign in'
                                          : 'New here? Create an account')),
                                  ActionButton('Email a reset link', () async {
                                    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                        .hasMatch(email.text.trim())) {
                                      throw StateError(
                                          'Enter your email first');
                                    }
                                    await ref
                                        .read(repositoryProvider)
                                        .client
                                        .auth
                                        .resetPasswordForEmail(
                                            email.text.trim(),
                                            redirectTo:
                                                'com.dastak.app://auth/callback');
                                    if (context.mounted) {
                                      toast(context,
                                          'Check your email for a password reset link.');
                                    }
                                  }),
                                  TextButton(
                                      onPressed: () => context.go('/'),
                                      child: const Text('Browse stores'))
                                ],
                              ])))))));
}
