import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/editor.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../customer/profile_menu.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageFrame('Your account',
      actions: const [ThemeToggle()],
      child: ref.watch(accountProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, s) => Failure(e, () => ref.invalidate(accountProvider)),
          data: (account) {
            if (account == null) {
              return Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const BrandMark(size: 72),
                        const SizedBox(height: 16),
                        const Text('Sign in to order, track deliveries and manage your account.',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                            onPressed: () => context.push('/login'),
                            child: const Text('Sign in to Dastak'))
                      ])));
            }
            final repo = ref.watch(repositoryProvider);
            final email = repo.client.auth.currentUser?.email;
            return ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                InitialAvatar(account.name.isEmpty ? (email ?? 'U') : account.name, radius: 30),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(account.name.isEmpty ? 'Hello!' : account.name, style: context.text.titleLarge),
                  if (email != null) Text(email, style: TextStyle(color: context.muted)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, children: [
                    StatusChip('info', label: statusLabel(account.role)),
                    if (account.status != 'active') StatusChip(account.status),
                  ])
                ]))
              ]),
              const SizedBox(height: 16),
              ActionButton('Edit name & phone', () async {
                final j = await repo.one('profiles', repo.uid);
                if (!context.mounted) return;
                await editRecord(context,
                    title: 'Your details',
                    initial: j,
                    fields: const [
                      EditField('display_name', 'Full name'),
                      EditField('phone', '10-digit mobile number (not OTP verified)', optional: true)
                    ], save: (d) async {
                  final phone = (d['phone'] as String?)?.replaceAll(RegExp(r'\D'), '');
                  if (phone != null && phone.isNotEmpty && !RegExp(r'^[6-9]\d{9}$').hasMatch(phone)) {
                    throw StateError('Enter a valid 10-digit mobile number');
                  }
                  if ((d['display_name'] as String).length < 2) throw StateError('Enter your name');
                  await repo.save('profiles', {...d, 'phone': phone == null || phone.isEmpty ? null : phone},
                      id: repo.uid);
                  ref.invalidate(accountProvider);
                });
              }, icon: Icons.edit_outlined, tonal: true),
              const SizedBox(height: 8),
              if (account.role != 'customer')
                _tile(context, Icons.dashboard_outlined, 'Open my workspace',
                    () => context.push(workspaceRoute(account.role))),
              _tile(context, Icons.location_on_outlined, 'Saved addresses', () => context.push('/addresses')),
              _tile(context, Icons.receipt_long_outlined, 'Order history & ratings', () => context.push('/orders')),
              _tile(context, Icons.notifications_outlined, 'Notifications', () => context.push('/notifications')),
              _tile(context, Icons.support_agent_outlined, 'Help & support', () => context.push('/support')),
              if (account.role == 'customer' || account.role == 'delivery')
                _tile(context, Icons.pedal_bike_outlined,
                    account.role == 'delivery' ? 'Partner application & documents' : 'Join as a delivery partner',
                    () => context.push('/partner/apply'),
                    subtitle: account.role == 'customer' ? 'Earn by delivering in your area' : null),
              if (account.role == 'customer' || account.role == 'vendor')
                _tile(context, Icons.storefront_outlined, 'Register your restaurant',
                    () => context.push('/vendor/apply'),
                    subtitle: 'List your restaurant or cafe on Dastak'),
              const Divider(height: 32),
              _tile(context, Icons.privacy_tip_outlined, 'Privacy policy', () => openPolicy(context, privacyUrl)),
              _tile(context, Icons.info_outline, 'About Dastak', () => showAboutDialog(
                  context: context,
                  applicationName: 'Dastak',
                  applicationVersion: '1.1.0',
                  applicationIcon: const BrandMark(size: 48),
                  applicationLegalese: 'Dil Se Ghar Tak • Local Delivery')),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: danger),
                  onPressed: () async {
                    if (await confirm(context, 'Log out?', 'You will need to sign in again.', yes: 'Log out')) {
                      if (context.mounted) await signOut(context, ref);
                    }
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Log out')),
              const SizedBox(height: 24),
              TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: danger),
                  onPressed: () => perform(context, () => deleteAccount(context, ref)),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Delete my account')),
            ]);
          }));
}

const privacyUrl = 'https://rohtak-dastak.vercel.app/privacy.html';

Future<void> openPolicy(BuildContext context, String url) async {
  if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication) && context.mounted) {
    toast(context, 'Could not open $url');
  }
}

Widget _tile(BuildContext context, IconData icon, String title, VoidCallback onTap, {String? subtitle}) =>
    ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: context.colors.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap);
