import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../customer/profile_menu.dart';

/// Shown after Google sign-in (or for older accounts) when the name or mobile number is missing.
class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key});
  @override
  ConsumerState<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends ConsumerState<CompleteProfileScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(), phone = TextEditingController();

  @override
  void initState() {
    super.initState();
    final repo = ref.read(repositoryProvider);
    final meta = repo.client.auth.currentUser?.userMetadata ?? {};
    final account = ref.read(accountProvider).valueOrNull;
    final current = account?.name ?? '';
    final emailPrefix = (repo.client.auth.currentUser?.email ?? '').split('@').first;
    name.text = current.isNotEmpty && current != emailPrefix ? current : '${meta['full_name'] ?? meta['name'] ?? current}';
    phone.text = account?.phone ?? '';
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) throw StateError('Please fix the highlighted fields');
    final repo = ref.read(repositoryProvider);
    await repo.save('profiles',
        {'display_name': name.text.trim(), 'phone': phone.text.replaceAll(RegExp(r'\D'), '')}, id: repo.uid);
    ref.invalidate(accountProvider);
    final account = await ref.read(accountProvider.future);
    if (mounted) context.go(workspaceRoute(account?.role ?? 'customer'));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
          child: Center(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Form(
                          key: form,
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            const Center(child: BrandMark(size: 64)),
                            const SizedBox(height: 16),
                            Text('Complete your profile', style: context.text.headlineMedium),
                            const SizedBox(height: 6),
                            const Text('Restaurants and delivery partners need your name and mobile number to deliver your orders.'),
                            const SizedBox(height: 16),
                            Field(name, 'Your name',
                                capitalization: TextCapitalization.words,
                                validate: (v) => v.length < 2 ? 'Enter your name' : null),
                            Field(phone, 'Mobile number',
                                keyboard: TextInputType.phone,
                                maxLength: 10,
                                hint: '10 digits, without +91',
                                validate: (v) => RegExp(r'^[6-9]\d{9}$').hasMatch(v.replaceAll(RegExp(r'\D'), ''))
                                    ? null
                                    : 'Enter a valid 10-digit mobile number'),
                            const SizedBox(height: 12),
                            ActionButton('Save and continue', save, icon: Icons.check),
                            TextButton(
                                onPressed: () => signOut(context, ref), child: const Text('Use a different account')),
                          ])))))));
}
