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
  final email = TextEditingController(), password = TextEditingController();
  final form = GlobalKey<FormState>();
  bool signup = false;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    final auth = ref.read(repositoryProvider).client.auth;
    if (widget.recovery) {
      await auth.updateUser(UserAttributes(password: password.text));
    } else if (signup) {
      final result = await auth.signUp(
          email: email.text.trim(),
          password: password.text,
          emailRedirectTo: 'com.dastak.app://auth/callback');
      if (result.session == null) {
        if (mounted) {
          toast(context, 'Check your email to confirm your account.');
        }
        return;
      }
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
                                    size: 64, color: Color(0xFFFF6B00)),
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
                                if (!widget.recovery)
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
                                              : 'Enter a valid email'),
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
