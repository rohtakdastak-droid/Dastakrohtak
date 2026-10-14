import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';
import 'providers.dart';
import 'theme.dart';

String errorText(Object error) {
  if (error is TimeoutException) {
    return 'Connection timed out. Check your connection and retry.';
  }
  if (error is AuthException) return error.message;
  if (error is PostgrestException) {
    if (error.code == '42501') {
      return 'You do not have permission for this action.';
    }
    if (error.code == 'PGRST202' || error.code == '42883') {
      return 'This feature needs the latest server update. Please contact the administrator.';
    }
    return error.message;
  }
  if (error is StorageException) return error.message;
  if (error is StateError) return error.message.toString();
  return 'Unable to complete this request. Check your connection and retry.';
}

void toast(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
Future<bool> perform(BuildContext context, Future<void> Function() task,
    {String? success}) async {
  try {
    await task();
    if (context.mounted && success != null) toast(context, success);
    return true;
  } catch (e) {
    if (context.mounted) toast(context, errorText(e));
    return false;
  }
}

class ActionButton extends StatefulWidget {
  final String label;
  final Future<void> Function() onPressed;
  final IconData? icon;
  final bool tonal;
  const ActionButton(this.label, this.onPressed,
      {this.icon, this.tonal = false, super.key});
  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final onPressed = busy
        ? null
        : () async {
            setState(() => busy = true);
            await perform(context, widget.onPressed);
            if (mounted) setState(() => busy = false);
          };
    final icon = busy
        ? const SizedBox.square(
            dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : Icon(widget.icon ?? Icons.arrow_forward, size: 18);
    final label = Text(busy ? 'Please wait…' : widget.label);
    return widget.tonal
        ? FilledButton.tonalIcon(onPressed: onPressed, icon: icon, label: label)
        : FilledButton.icon(onPressed: onPressed, icon: icon, label: label);
  }
}

class PageFrame extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? floatingBottom;
  final bool customerNav;
  const PageFrame(this.title,
      {required this.child,
      this.actions,
      this.floatingBottom,
      this.customerNav = true,
      super.key});
  @override
  Widget build(BuildContext context) {
    String path = '/home';
    try {
      path = GoRouterState.of(context).uri.path;
    } catch (_) {}
    return Scaffold(
        appBar: AppBar(title: Text(title), actions: actions),
        body: SafeArea(
            child: Stack(children: [
          Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 850),
                  child: child)),
          if (floatingBottom != null)
            Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(child: floatingBottom!))
        ])),
        bottomNavigationBar: !customerNav
            ? null
            : NavigationBar(
                selectedIndex: switch (path) {
                  '/cart' => 1,
                  '/orders' => 2,
                  '/profile' => 3,
                  _ => 0
                },
                onDestinationSelected: (i) =>
                    context.go(['/home', '/cart', '/orders', '/profile'][i]),
                destinations: const [
                    NavigationDestination(
                        icon: Icon(Icons.storefront_outlined),
                        label: 'Discover'),
                    NavigationDestination(
                        icon: Icon(Icons.shopping_bag_outlined), label: 'Bag'),
                    NavigationDestination(
                        icon: Icon(Icons.receipt_long_outlined),
                        label: 'Orders'),
                    NavigationDestination(
                        icon: Icon(Icons.person_outline), label: 'Account')
                  ]));
  }
}

class Failure extends StatelessWidget {
  final Object error;
  final VoidCallback retry;
  const Failure(this.error, this.retry, {super.key});
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off, size: 44, color: context.muted),
            const SizedBox(height: 16),
            Text(errorText(error), textAlign: TextAlign.center),
            TextButton(onPressed: retry, child: const Text('Try again'))
          ])));
}

class Empty extends StatelessWidget {
  final String text;
  final IconData icon;
  const Empty(this.text, {this.icon = Icons.inbox_outlined, super.key});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 40, color: context.muted),
        const SizedBox(height: 10),
        Text(text,
            textAlign: TextAlign.center, style: TextStyle(color: context.muted))
      ])));
}

class RemoteList extends ConsumerStatefulWidget {
  final String title;
  final Future<List<Json>> Function(int) load;
  final Widget Function(Json, VoidCallback) item;
  final List<Widget> header;
  final String? watch;
  final Widget? floatingBottom;
  final List<Widget>? actions;
  final bool customerNav;
  final String emptyText;
  final bool showUpdated;
  const RemoteList(
      {required this.title,
      required this.load,
      required this.item,
      this.header = const [],
      this.watch,
      this.floatingBottom,
      this.actions,
      this.customerNav = true,
      this.emptyText = 'Nothing here yet.',
      this.showUpdated = false,
      super.key});
  @override
  ConsumerState<RemoteList> createState() => _RemoteListState();
}

class _RemoteListState extends ConsumerState<RemoteList> {
  List<Json> data = [];
  Object? error;
  bool busy = true, more = true;
  int page = 0;
  int request = 0;
  DateTime? updated;
  RealtimeChannel? channel;
  SupabaseClient? realtime;
  Timer? debounce;
  @override
  void initState() {
    super.initState();
    load(true);
    if (widget.watch != null) {
      final repo = ref.read(repositoryProvider);
      realtime = repo.client;
      channel = repo.watch(widget.watch!, () {
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 400), () => load(true));
      });
    }
  }

  Future<void> load(bool reset) async {
    if (!mounted) return;
    final ticket = ++request;
    setState(() => busy = true);
    try {
      final next = await widget.load(reset ? 0 : page + 1);
      if (!mounted || ticket != request) return;
      setState(() {
        data = reset ? next : [...data, ...next];
        page = reset ? 0 : page + 1;
        more = next.length == 30;
        error = null;
        updated = DateTime.now();
      });
    } catch (e) {
      if (mounted && ticket == request) setState(() => error = e);
    } finally {
      if (mounted && ticket == request) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    if (channel != null) realtime?.removeChannel(channel!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageFrame(widget.title,
      actions: widget.actions,
      customerNav: widget.customerNav,
      floatingBottom: widget.floatingBottom,
      child: RefreshIndicator(
          onRefresh: () => load(true),
          child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, widget.floatingBottom != null ? 100 : 24),
              children: [
                ...widget.header,
                if (busy) const LinearProgressIndicator(),
                if (widget.showUpdated && updated != null && !busy)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('Updated ${clock(updated!)} • pull to refresh',
                          style: TextStyle(fontSize: 11, color: context.muted))),
                if (error != null) Failure(error!, () => load(true)),
                if (!busy && data.isEmpty && error == null)
                  Empty(widget.emptyText),
                for (final row in data) widget.item(row, () => load(true)),
                if (more && !busy && data.isNotEmpty)
                  TextButton(
                      onPressed: () => load(false),
                      child: const Text('Load more'))
              ])));
}

class RoleGuard extends ConsumerWidget {
  final List<String> roles;
  final Widget child;
  const RoleGuard({required this.roles, required this.child, super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(accountProvider).when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, s) =>
              Scaffold(body: Failure(e, () => ref.invalidate(accountProvider))),
          data: (account) {
            if (account == null) {
              return Scaffold(
                  body: Center(
                      child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: FilledButton(
                              onPressed: () => context.go('/login'),
                              child: const Text('Sign in')))));
            }
            if (!roles.contains(account.role)) {
              return Scaffold(
                  appBar: AppBar(),
                  body: const Empty(
                      'This workspace is not available to your account.',
                      icon: Icons.lock_outline));
            }
            if (account.status == 'suspended' && !roles.contains('customer')) {
              return Scaffold(
                  appBar: AppBar(),
                  body: const Empty(
                      'Your account is suspended. Contact support for help.',
                      icon: Icons.block));
            }
            return child;
          });
}

class Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool secret, requiredValue;
  final TextInputType? keyboard;
  final int lines;
  final String? hint;
  final String? Function(String)? validate;
  final int? maxLength;
  final TextCapitalization capitalization;
  final bool enabled;
  const Field(this.controller, this.label,
      {this.secret = false,
      this.requiredValue = true,
      this.keyboard,
      this.lines = 1,
      this.hint,
      this.validate,
      this.maxLength,
      this.capitalization = TextCapitalization.none,
      this.enabled = true,
      super.key});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
          controller: controller,
          obscureText: secret,
          maxLines: lines,
          minLines: 1,
          enabled: enabled,
          maxLength: maxLength,
          keyboardType: keyboard,
          textCapitalization: capitalization,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: InputDecoration(
              labelText: requiredValue ? '$label *' : label,
              helperText: hint,
              helperMaxLines: 2,
              counterText: ''),
          validator: (v) {
            final text = (v ?? '').trim();
            if (requiredValue && text.isEmpty) return 'Required';
            if (text.isNotEmpty && validate != null) return validate!(text);
            return null;
          }));
}

class Photo extends StatelessWidget {
  final String? url;
  final double height;
  final IconData placeholder;
  final double radius;
  const Photo(this.url,
      {this.height = 150,
      this.placeholder = Icons.storefront,
      this.radius = 18,
      super.key});
  @override
  Widget build(BuildContext context) {
    final fallback = Container(
        height: height,
        color: context.tint,
        child: Center(
            child: Icon(placeholder,
                size: height > 80 ? 44 : 26, color: context.colors.primary)));
    return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: url == null
            ? fallback
            : Image.network(url!,
                height: height,
                width: double.infinity,
                fit: BoxFit.cover,
                cacheHeight: (height * 2.5).round(),
                loadingBuilder: (c, child, progress) =>
                    progress == null ? child : fallback,
                errorBuilder: (a, b, c) => fallback));
  }
}

String clock(DateTime t) {
  final l = t.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

String stamp(dynamic iso) {
  if (iso == null) return '—';
  final t = DateTime.tryParse('$iso')?.toLocal();
  if (t == null) return '—';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${t.day} ${months[t.month - 1]} ${t.year}, ${clock(t)}';
}

String ago(dynamic iso) {
  final t = DateTime.tryParse('$iso');
  if (t == null) return '';
  final d = DateTime.now().toUtc().difference(t.toUtc());
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

class StatTile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;
  final String? hint;
  const StatTile(this.label, this.value, this.icon,
      {this.color, this.onTap, this.hint, super.key});
  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.primary;
    return Material(
        color: c.withValues(alpha: context.dark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Icon(icon, color: c, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        Text(label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: context.muted)),
                        Text(value,
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: c)),
                        if (hint != null)
                          Text(hint!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10, color: context.muted))
                      ])),
                  if (onTap != null)
                    Icon(Icons.chevron_right, size: 16, color: context.muted)
                ]))));
  }
}

class StatGrid extends StatelessWidget {
  final List<Widget> children;
  const StatGrid(this.children, {super.key});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (c, box) {
        final columns = box.maxWidth > 700 ? 4 : (box.maxWidth > 330 ? 2 : 1);
        return Column(children: [
          for (var i = 0; i < children.length; i += columns) ...[
            if (i > 0) const SizedBox(height: 10),
            IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var j = 0; j < columns; j++) ...[
                if (j > 0) const SizedBox(width: 10),
                Expanded(
                    child: i + j < children.length
                        ? ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 74), child: children[i + j])
                        : const SizedBox()),
              ]
            ])),
          ]
        ]);
      });
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {this.trailing, super.key});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Row(children: [
        Expanded(child: Text(text, style: context.text.titleMedium)),
        if (trailing != null) trailing!
      ]));
}

Color statusColor(String status) => switch (status) {
      'approved' ||
      'active' ||
      'verified' ||
      'paid' ||
      'delivered' ||
      'visible' ||
      'open' =>
        success,
      'pending' ||
      'pending_verification' ||
      'submitted' ||
      'processing' ||
      'payment_review' ||
      'vendor_confirmation' ||
      'preparing' ||
      'ready_for_pickup' ||
      'assigned' ||
      'picked_up' ||
      'out_for_delivery' =>
        warning,
      'rejected' ||
      'suspended' ||
      'failed' ||
      'cancelled' ||
      'hidden' ||
      'closed' =>
        danger,
      'action_required' || 'pending_payment' || 'unpaid' => const Color(0xFFEA580C),
      _ => const Color(0xFF64748B)
    };

String statusLabel(String status) => switch (status) {
      'pending_verification' => 'Pending verification',
      'action_required' => 'Action required',
      'vendor_confirmation' => 'Waiting for restaurant',
      'pending_payment' => 'Awaiting payment',
      'payment_review' => 'Payment under review',
      'ready_for_pickup' => 'Ready for pickup',
      'out_for_delivery' => 'Out for delivery',
      'picked_up' => 'Picked up',
      'assigned' => 'Partner assigned',
      'submitted' => 'Pending verification',
      'verified' => 'Verified',
      'unpaid' => 'Unpaid',
      _ => status.isEmpty
          ? '—'
          : '${status[0].toUpperCase()}${status.substring(1).replaceAll('_', ' ')}'
    };

class StatusChip extends StatelessWidget {
  final String status;
  final String? label;
  const StatusChip(this.status, {this.label, super.key});
  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    // Capped width so a long label wraps instead of pushing its row off screen.
    return Container(
        constraints: const BoxConstraints(maxWidth: 130),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: c.withValues(alpha: context.dark ? 0.22 : 0.12),
            borderRadius: BorderRadius.circular(12)),
        child: Text(label ?? statusLabel(status),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: c, fontWeight: FontWeight.w700, fontSize: 12)));
  }
}

class InfoRow extends StatelessWidget {
  final String label;
  final String? value;
  final bool copyable;
  const InfoRow(this.label, this.value, {this.copyable = false, super.key});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 130,
            child: Text(label,
                style: TextStyle(color: context.muted, fontSize: 13))),
        Expanded(
            child: copyable
                ? SelectableText(value ?? '—',
                    style: const TextStyle(fontWeight: FontWeight.w600))
                : Text(value == null || value!.isEmpty ? '—' : value!,
                    style: const TextStyle(fontWeight: FontWeight.w600)))
      ]));
}

class Panel extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;
  final Color? color;
  const Panel(this.children,
      {this.padding = const EdgeInsets.all(16), this.color, super.key});
  @override
  Widget build(BuildContext context) => Card(
      color: color,
      child: Padding(
          padding: padding,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children)));
}

class Notice extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  final Widget? action;
  const Notice(this.text,
      {this.icon = Icons.info_outline,
      this.color = const Color(0xFF0EA5E9),
      this.action,
      super.key});
  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: color.withValues(alpha: context.dark ? 0.18 : 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35))),
      child: Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600))),
        if (action != null) action!
      ]));
}

Future<bool> confirm(BuildContext context, String title, String message,
    {String yes = 'Confirm', bool destructive = false}) async {
  final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Back')),
                FilledButton(
                    style: destructive
                        ? FilledButton.styleFrom(
                            backgroundColor: danger,
                            minimumSize: const Size(0, 44))
                        : FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(yes))
              ]));
  return result == true;
}

Future<String?> askText(BuildContext context, String title,
    {String? hint,
    String? initial,
    int minLength = 1,
    TextInputType? keyboard,
    String action = 'Continue'}) async {
  final controller = TextEditingController(text: initial);
  String? problem;
  final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) => AlertDialog(
                  title: Text(title),
                  content: TextField(
                      controller: controller,
                      autofocus: true,
                      keyboardType: keyboard,
                      maxLines: keyboard == null ? 3 : 1,
                      decoration:
                          InputDecoration(hintText: hint, errorText: problem)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel')),
                    FilledButton(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 44)),
                        onPressed: () {
                          final v = controller.text.trim();
                          if (v.length < minLength) {
                            set(() => problem = minLength > 1
                                ? 'Enter at least $minLength characters'
                                : 'Required');
                            return;
                          }
                          Navigator.pop(ctx, v);
                        },
                        child: Text(action))
                  ])));
  Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
  return result;
}

class StarInput extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final double size;
  const StarInput(this.value, this.onChanged, {this.size = 34, super.key});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
              tooltip: '$i star${i == 1 ? '' : 's'}',
              visualDensity: VisualDensity.compact,
              onPressed: () => onChanged(i),
              icon: Icon(i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: size, color: const Color(0xFFF59E0B)))
      ]);
}

class Stars extends StatelessWidget {
  final num? rating;
  final int count;
  const Stars(this.rating, this.count, {super.key});
  @override
  Widget build(BuildContext context) => count == 0 || rating == null
      ? Text('New', style: TextStyle(color: context.muted, fontSize: 12))
      : Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF59E0B)),
          const SizedBox(width: 2),
          Text('${rating!.toStringAsFixed(1)} ($count)',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))
        ]);
}

class Range {
  final String label;
  final DateTime from, to;
  const Range(this.label, this.from, this.to);
  static Range today() {
    final n = DateTime.now();
    final start = DateTime(n.year, n.month, n.day);
    return Range('Today', start, start.add(const Duration(days: 1)));
  }

  static Range days(int d) {
    final n = DateTime.now();
    final end = DateTime(n.year, n.month, n.day).add(const Duration(days: 1));
    return Range('$d days', end.subtract(Duration(days: d)), end);
  }

  Json get params => {
        'p_from': from.toUtc().toIso8601String(),
        'p_to': to.toUtc().toIso8601String()
      };
}

class RangeChips extends StatelessWidget {
  final Range value;
  final ValueChanged<Range> onChanged;
  const RangeChips(this.value, this.onChanged, {super.key});
  @override
  Widget build(BuildContext context) {
    final options = [Range.today(), Range.days(7), Range.days(30)];
    return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final r in options)
            Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                    label: Text(r.label),
                    selected: value.label == r.label,
                    onSelected: (_) => onChanged(r))),
          ActionChip(
              avatar: const Icon(Icons.date_range, size: 18),
              label: Text(options.any((r) => r.label == value.label)
                  ? 'Custom'
                  : value.label),
              onPressed: () async {
                final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now().add(const Duration(days: 1)));
                if (picked != null) {
                  onChanged(Range(
                      '${picked.start.day}/${picked.start.month}–${picked.end.day}/${picked.end.month}',
                      picked.start,
                      picked.end.add(const Duration(days: 1))));
                }
              })
        ]));
  }
}

Future<void> copyText(BuildContext context, String text, String what) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) toast(context, '$what copied to clipboard');
}

String csv(List<List<Object?>> rows) => rows
    .map((r) => r.map((c) {
          final s = '${c ?? ''}';
          return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
        }).join(','))
    .join('\n');

class ThemeToggle extends ConsumerWidget {
  const ThemeToggle({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = context.dark;
    return IconButton(
        tooltip: dark ? 'Switch to light mode' : 'Switch to dark mode',
        onPressed: () =>
            ref.read(themeModeProvider.notifier).toggle(Theme.of(context).brightness),
        icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined));
  }
}

class InitialAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double radius;
  const InitialAvatar(this.name, {this.imageUrl, this.radius = 18, super.key});
  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return CircleAvatar(
        radius: radius,
        backgroundColor: context.colors.primary,
        foregroundImage: imageUrl == null ? null : NetworkImage(imageUrl!),
        child: Text(initial,
            style: TextStyle(
                color: context.colors.onPrimary,
                fontWeight: FontWeight.w800,
                fontSize: radius * 0.9)));
  }
}

class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({this.size = 44, super.key});
  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Image.asset('assets/logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          semanticLabel: 'Dastak logo'));
}
