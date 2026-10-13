import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SignOutScope;
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../cart/cart_controller.dart';
import '../notifications/push_service.dart';

Future<void> signOut(BuildContext context, WidgetRef ref) async {
  try {
    await ref.read(pushServiceProvider).disable();
  } catch (_) {}
  await ref.read(repositoryProvider).client.auth.signOut();
  await ref.read(cartProvider.notifier).clear();
  ref.invalidate(accountProvider);
  if (context.mounted) context.go('/home');
}

Future<void> deleteAccount(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(repositoryProvider);
  final ok = await confirm(
      context,
      'Delete your account?',
      'This permanently deletes your name, phone, email, saved addresses, notifications, support chats, '
          'partner documents and payout QR, and you will not be able to sign in again.\n\n'
          'Past orders, payments and earnings are kept without your name for accounting, as the law requires.',
      yes: 'Continue',
      destructive: true);
  if (!ok || !context.mounted) return;
  final blockers = List<String>.from((await repo.rpc('account_deletion_blockers') as List?) ?? const []);
  if (!context.mounted) return;
  if (blockers.isNotEmpty) {
    await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Account cannot be deleted yet'),
                content: Text(blockers.map((b) => '• $b').join('\n')),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))]));
    return;
  }
  final typed = await askText(context, 'Type DELETE to permanently delete your account',
      hint: 'DELETE', minLength: 6, action: 'Delete account');
  if (typed == null) return;
  if (typed.trim().toUpperCase() != 'DELETE') throw StateError('Account not deleted: you did not type DELETE');
  final docs = repo.client.storage.from('partner-docs');
  final files = await docs.list(path: repo.uid);
  if (files.isNotEmpty) await docs.remove([for (final f in files) '${repo.uid}/${f.name}']);
  await repo.rpc('delete_my_account', {'p_confirm': 'DELETE'});
  final prefs = ref.read(preferencesProvider);
  await prefs.remove('delivery_point');
  await prefs.remove('checkout.${repo.uid}');
  await ref.read(cartProvider.notifier).clear();
  try {
    await ref.read(pushServiceProvider).disable();
  } catch (_) {}
  try {
    await repo.client.auth.signOut(scope: SignOutScope.local);
  } catch (_) {}
  ref.invalidate(accountProvider);
  if (context.mounted) {
    toast(context, 'Your account has been deleted.');
    context.go('/home');
  }
}

String workspaceRoute(String role) => switch (role) {
      'vendor' => '/vendor',
      'delivery' => '/delivery',
      'admin' => '/admin',
      _ => '/home'
    };

Future<void> showProfileMenu(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(repositoryProvider);
  final account = ref.read(accountProvider).valueOrNull;
  if (account == null) {
    context.push('/login');
    return;
  }
  Map<String, dynamic>? profile;
  try {
    profile = await repo.one('profiles', account.id);
  } catch (_) {}
  if (!context.mounted) return;
  final email = repo.client.auth.currentUser?.email;
  void go(BuildContext sheet, String route) {
    Navigator.pop(sheet);
    context.push(route);
  }

  await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
          child: ConstrainedBox(
              constraints:
                  BoxConstraints(maxHeight: MediaQuery.of(sheet).size.height * 0.85),
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
                Row(children: [
                  InitialAvatar(account.name.isEmpty ? (email ?? 'U') : account.name,
                      radius: 28,
                      imageUrl: profile?['avatar_path'] == null
                          ? null
                          : repo.imageUrl(profile!['avatar_path'], bucket: 'product-images')),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(account.name.isEmpty ? 'Your account' : account.name,
                        style: sheet.text.titleLarge),
                    if ((profile?['phone'] ?? '').toString().isNotEmpty)
                      Text('+91 ${profile!['phone']}', style: TextStyle(color: sheet.muted)),
                    if (email != null) Text(email, style: TextStyle(color: sheet.muted, fontSize: 12)),
                  ])),
                ]),
                const SizedBox(height: 12),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(sheet.dark ? Icons.dark_mode : Icons.light_mode),
                    title: const Text('Dark mode'),
                    value: sheet.dark,
                    onChanged: (_) => ref
                        .read(themeModeProvider.notifier)
                        .toggle(Theme.of(sheet).brightness)),
                const Divider(),
                if (account.role != 'customer')
                  _item(sheet, Icons.dashboard_outlined, 'Open my workspace',
                      () => go(sheet, workspaceRoute(account.role))),
                _item(sheet, Icons.location_on_outlined, 'Saved addresses', () => go(sheet, '/addresses')),
                _item(sheet, Icons.receipt_long_outlined, 'Order history', () => go(sheet, '/orders')),
                _item(sheet, Icons.star_outline, 'Ratings & reviews',
                    () => go(sheet, '/orders'), subtitle: 'Rate delivered orders from your order history'),
                _item(sheet, Icons.notifications_outlined, 'Notifications', () => go(sheet, '/notifications')),
                _item(sheet, Icons.manage_accounts_outlined, 'Account settings', () => go(sheet, '/profile')),
                _item(sheet, Icons.support_agent_outlined, 'Help & support', () => go(sheet, '/support')),
                const Divider(),
                _item(sheet, Icons.logout, 'Log out', () async {
                  Navigator.pop(sheet);
                  if (await confirm(context, 'Log out?', 'You will need to sign in again to place orders.',
                      yes: 'Log out')) {
                    if (context.mounted) await signOut(context, ref);
                  }
                }, color: danger),
              ]))));
}

Widget _item(BuildContext context, IconData icon, String title, VoidCallback onTap,
        {String? subtitle, Color? color}) =>
    ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: color),
        title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap);
