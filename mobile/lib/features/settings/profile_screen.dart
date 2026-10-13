import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../core/editor.dart';
import '../cart/cart_controller.dart';
import '../notifications/push_service.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageFrame('Your account',
      child: ref.watch(accountProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, s) => Failure(e, () => ref.invalidate(accountProvider)),
          data: (account) {
            if (account == null) {
              return Center(
                  child: FilledButton(
                      onPressed: () => context.push('/login'),
                      child: const Text('Sign in to Dastak')));
            }
            final repo = ref.watch(repositoryProvider);
            return ListView(padding: const EdgeInsets.all(24), children: [
              Text('Hello, ${account.name}',
                  style: Theme.of(context).textTheme.headlineMedium),
              Text('${account.role} · ${account.status}'),
              const SizedBox(height: 24),
              ActionButton('Edit profile', () async {
                final j = await repo.one('profiles', repo.uid);
                if (!context.mounted) return;
                await editRecord(context,
                    title: 'Your details',
                    initial: j,
                    fields: const [
                      EditField('display_name', 'Display name'),
                      EditField('phone', 'Phone number (not OTP verified)',
                          optional: true)
                    ], save: (d) async {
                  if (d['phone'] != null &&
                      !RegExp(r'^\+?[0-9]{10,15}$').hasMatch(d['phone'])) {
                    throw StateError('Enter a valid phone number');
                  }
                  await repo.save('profiles', d, id: repo.uid);
                  ref.invalidate(accountProvider);
                });
              }),
              for (final link in [
                ('Saved addresses', '/addresses'),
                ('Order history', '/orders'),
                ('Notifications', '/notifications'),
                if (account.role == 'vendor') ('Vendor workspace', '/vendor'),
                if (account.role == 'delivery')
                  ('Delivery workspace', '/delivery'),
                if (account.role == 'admin') ('Admin workspace', '/admin')
              ])
                ListTile(
                    title: Text(link.$1),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(link.$2)),
              const SizedBox(height: 24),
              ActionButton('Sign out', () async {
                await ref.read(pushServiceProvider).disable();
                await repo.client.auth.signOut();
                await ref.read(cartProvider.notifier).clear();
                ref.invalidate(accountProvider);
                if (context.mounted) context.go('/home');
              }),
              TextButton(
                  onPressed: () => showLicensePage(
                      context: context,
                      applicationName: 'Dastak',
                      applicationVersion: '1.0.0'),
                  child: const Text('Open-source licenses')),
            ]);
          }));
}
