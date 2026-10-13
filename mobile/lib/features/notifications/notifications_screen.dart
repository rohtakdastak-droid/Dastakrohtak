import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';
import 'push_service.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    return RemoteList(
        title: 'Notifications',
        watch: 'notifications',
        load: (p) =>
            repo.rows('notifications', filters: {'user_id': repo.uid}, page: p),
        header: [
          ActionButton('Enable push notifications',
              () => ref.read(pushServiceProvider).enable()),
          if (!PushService.configured)
            const Text(
                'Native push setup is unavailable in this build. Your in-app inbox remains available.')
        ],
        item: (j, reload) => Card(
            child: ListTile(
                leading: Icon(j['read_at'] == null
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_none),
                title: Text(j['title']),
                subtitle: Text(j['body'] ?? ''),
                onTap: () async {
                  if (await perform(
                      context,
                      () => repo.save('notifications',
                          {'read_at': DateTime.now().toUtc().toIso8601String()},
                          id: j['id']))) {
                    reload();
                    if (context.mounted && j['order_id'] != null) {
                      context.push('/orders/${j['order_id']}');
                    }
                  }
                })));
  }
}
