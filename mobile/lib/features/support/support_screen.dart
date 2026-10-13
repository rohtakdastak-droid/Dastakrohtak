import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

const supportCategories = ['Order issue', 'Payment', 'Delivery', 'Account', 'Partner payout', 'Restaurant', 'Other'];

class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({super.key});
  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  int generation = 0;
  String? status = 'open';

  Future<void> create() async {
    final repo = ref.read(repositoryProvider);
    String category = supportCategories.first;
    final description = TextEditingController();
    final orderNumber = TextEditingController();
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, set) => AlertDialog(
                    title: const Text('How can we help?'),
                    content: SingleChildScrollView(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                      DropdownButtonFormField<String>(
                          initialValue: category,
                          decoration: const InputDecoration(labelText: 'Topic'),
                          items: [for (final cat in supportCategories) DropdownMenuItem(value: cat, child: Text(cat))],
                          onChanged: (v) => set(() => category = v!)),
                      const SizedBox(height: 8),
                      TextField(
                          controller: orderNumber,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(labelText: 'Order number (optional)', hintText: 'DST-XXXXXXXX')),
                      const SizedBox(height: 8),
                      TextField(
                          controller: description,
                          maxLines: 4,
                          maxLength: 2000,
                          decoration: const InputDecoration(labelText: 'Describe the problem')),
                    ])),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      FilledButton(
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Send'))
                    ])));
    if (ok != true || !mounted) return;
    await perform(context, () async {
      if (description.text.trim().length < 5) throw StateError('Please describe the problem (at least 5 characters)');
      String? orderId;
      final number = orderNumber.text.trim().toUpperCase();
      if (number.isNotEmpty) {
        final match = await repo.client.from('orders').select('id').eq('order_number', number).maybeSingle();
        if (match == null) throw StateError('Order $number was not found in your orders');
        orderId = match['id'];
      }
      await repo.client.from('support_tickets').insert({
        'customer_id': repo.uid,
        'category': category,
        'description': description.text.trim(),
        'order_id': orderId,
      });
      if (mounted) setState(() => generation++);
    }, success: 'Request sent. We will reply here and notify you.');
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final role = ref.watch(accountProvider).valueOrNull?.role;
    final admin = role == 'admin';
    return RemoteList(
        key: ValueKey('$generation/$status'),
        title: admin ? 'Support tickets' : 'Help & support',
        customerNav: role == null || role == 'customer',
        emptyText: admin ? 'No tickets in this list.' : 'No support requests yet.',
        load: (p) async {
          var q = repo.client.from('support_tickets').select();
          if (!admin) q = q.eq('customer_id', repo.uid);
          if (status != null) q = q.inFilter('status', status == 'open' ? ['open', 'in_progress'] : [status!]);
          final data = await q.order('created_at', ascending: false).range(p * 30, p * 30 + 29);
          return data.map((j) => Map<String, dynamic>.from(j)).toList();
        },
        header: [
          if (!admin) ...[
            ActionButton('New support request', create, icon: Icons.add_comment_outlined),
            const SizedBox(height: 8),
          ],
          Wrap(spacing: 6, children: [
            for (final s in ['open', 'resolved', 'closed', null])
              ChoiceChip(label: Text(s == null ? 'All' : statusLabel(s)), selected: status == s, onSelected: (_) => setState(() => status = s))
          ]),
          const SizedBox(height: 8),
        ],
        item: (t, reload) => Card(
            child: ListTile(
                title: Text('${t['category']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${t['description']}\n${stamp(t['created_at'])}', maxLines: 3, overflow: TextOverflow.ellipsis),
                isThreeLine: true,
                trailing: StatusChip('${t['status']}'),
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TicketScreen(t)));
                  reload();
                })));
  }
}

class TicketScreen extends ConsumerStatefulWidget {
  final Json ticket;
  const TicketScreen(this.ticket, {super.key});
  @override
  ConsumerState<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends ConsumerState<TicketScreen> {
  final message = TextEditingController();
  late Json ticket = widget.ticket;
  late Future<List<Json>> messages = load();

  Future<List<Json>> load() async {
    final data = await ref
        .read(repositoryProvider)
        .client
        .from('support_messages')
        .select()
        .eq('ticket_id', ticket['id'])
        .order('created_at')
        .limit(200);
    return data.map((j) => Map<String, dynamic>.from(j)).toList();
  }

  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  Future<void> setStatus(String status) async {
    await ref.read(repositoryProvider).save('support_tickets', {'status': status}, id: ticket['id']);
    setState(() => ticket = {...ticket, 'status': status});
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(repositoryProvider);
    final admin = ref.watch(accountProvider).valueOrNull?.role == 'admin';
    final closed = ticket['status'] == 'closed';
    return Scaffold(
        appBar: AppBar(title: Text('${ticket['category']}'), actions: [
          if (admin && !closed)
            PopupMenuButton<String>(
                tooltip: 'Change status',
                onSelected: (s) => perform(context, () => setStatus(s)),
                itemBuilder: (_) => [
                      for (final s in ['in_progress', 'resolved', 'closed']) PopupMenuItem(value: s, child: Text('Mark ${statusLabel(s).toLowerCase()}'))
                    ])
          else if (!closed)
            TextButton(onPressed: () => perform(context, () => setStatus('closed'), success: 'Request closed'), child: const Text('Close'))
        ]),
        body: SafeArea(
            child: Column(children: [
          Expanded(
              child: FutureBuilder<List<Json>>(
                  future: messages,
                  builder: (c, s) => ListView(padding: const EdgeInsets.all(16), children: [
                        Panel([
                          Row(children: [Expanded(child: Text(stamp(ticket['created_at']))), StatusChip('${ticket['status']}')]),
                          const SizedBox(height: 6),
                          Text('${ticket['description']}'),
                          if (ticket['order_id'] != null)
                            TextButton(onPressed: () => context.push('/orders/${ticket['order_id']}'), child: const Text('View related order')),
                        ]),
                        if (s.hasError) Failure(s.error!, () => setState(() => messages = load())),
                        if (s.hasData)
                          for (final m in s.data!)
                            Align(
                                alignment: m['sender_id'] == repo.uid ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                    constraints: const BoxConstraints(maxWidth: 320),
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                        color: m['sender_id'] == repo.uid ? context.colors.primary.withValues(alpha: 0.15) : context.tint,
                                        borderRadius: BorderRadius.circular(14)),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text('${m['message']}'),
                                      Text(stamp(m['created_at']), style: TextStyle(fontSize: 10, color: context.muted)),
                                    ]))),
                      ]))),
          if (!closed)
            Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(children: [
                  Expanded(
                      child: TextField(
                          controller: message,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 2000,
                          decoration: const InputDecoration(hintText: 'Write a message', counterText: ''))),
                  const SizedBox(width: 8),
                  IconButton.filled(
                      tooltip: 'Send',
                      onPressed: () => perform(context, () async {
                            if (message.text.trim().isEmpty) return;
                            await repo.client
                                .from('support_messages')
                                .insert({'ticket_id': ticket['id'], 'sender_id': repo.uid, 'message': message.text.trim()});
                            message.clear();
                            setState(() => messages = load());
                          }),
                      icon: const Icon(Icons.send)),
                ])),
        ])));
  }
}
