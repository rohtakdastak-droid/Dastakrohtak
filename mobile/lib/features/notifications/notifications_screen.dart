import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'push_service.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  int generation = 0;
  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final role = ref.watch(accountProvider).valueOrNull?.role;
    return RemoteList(
        key: ValueKey(generation),
        title: 'Notifications',
        watch: 'notifications',
        customerNav: role == null || role == 'customer',
        emptyText: 'You have no notifications yet.',
        actions: [
          IconButton(
              tooltip: 'Mark all as read',
              onPressed: () => perform(context, () async {
                    await repo.client
                        .from('notifications')
                        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
                        .eq('user_id', repo.uid)
                        .isFilter('read_at', null);
                    if (mounted) setState(() => generation++);
                  }),
              icon: const Icon(Icons.done_all))
        ],
        load: (p) => repo.rows('notifications', filters: {'user_id': repo.uid}, page: p),
        header: [
          if (PushService.configured)
            Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                    onPressed: () => perform(context, () => ref.read(pushServiceProvider).enable(),
                        success: 'Phone notifications are on for this device'),
                    icon: const Icon(Icons.notifications_active_outlined, size: 18),
                    label: const Text('Turn on phone notifications')))
          else
            Text('Phone push notifications are not set up in this build. This inbox still updates live.',
                style: TextStyle(fontSize: 12, color: context.muted)),
          const SizedBox(height: 8),
        ],
        item: (j, reload) {
          final unread = j['read_at'] == null;
          return Card(
              color: unread ? context.tint : null,
              child: ListTile(
                  leading: Icon(unread ? Icons.notifications_active : Icons.notifications_none,
                      color: unread ? context.colors.primary : context.muted),
                  title: Text(j['title'], style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w500)),
                  subtitle: Text([if ((j['body'] ?? '').toString().isNotEmpty) j['body'], ago(j['created_at'])].join('\n')),
                  onTap: () async {
                    if (unread) {
                      await perform(context,
                          () => repo.save('notifications', {'read_at': DateTime.now().toUtc().toIso8601String()}, id: j['id']));
                      reload();
                    }
                    if (!context.mounted) return;
                    if (j['order_id'] != null) {
                      context.push('/orders/${j['order_id']}');
                    } else if ('${j['type']}'.startsWith('partner') || j['type'] == 'payout' || j['type'] == 'earning') {
                      context.push(role == 'admin' ? '/admin/partners' : '/delivery');
                    } else if (j['type'] == 'support') {
                      context.push('/support');
                    } else if (j['type'] == 'vendor_application') {
                      context.push(role == 'admin' ? '/admin/vendor-applications' : '/vendor');
                    }
                  }));
        });
  }
}
