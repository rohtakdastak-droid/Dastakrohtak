import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';
import 'providers.dart';

String errorText(Object error) {
  if (error is TimeoutException) {
    return 'Connection timed out. Check your connection and retry.';
  }
  if (error is AuthException) return error.message;
  if (error is PostgrestException) {
    return error.code == '42501'
        ? 'You do not have permission for this action.'
        : error.message;
  }
  if (error is StateError) return error.message.toString();
  return 'Unable to complete this request. Check your connection and retry.';
}

void toast(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
  const ActionButton(this.label, this.onPressed, {this.icon, super.key});
  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool busy = false;
  @override
  Widget build(BuildContext context) => FilledButton.icon(
      onPressed: busy
          ? null
          : () async {
              setState(() => busy = true);
              await perform(context, widget.onPressed);
              if (mounted) setState(() => busy = false);
            },
      icon: busy
          ? const SizedBox.square(
              dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(widget.icon ?? Icons.arrow_forward, size: 18),
      label: Text(busy ? 'Please wait…' : widget.label));
}

class PageFrame extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? floatingBottom;
  const PageFrame(this.title,
      {required this.child, this.actions, this.floatingBottom, super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
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
      bottomNavigationBar: NavigationBar(
          selectedIndex: switch (GoRouterState.of(context).uri.path) {
            '/cart' => 1,
            '/orders' => 2,
            '/profile' => 3,
            _ => 0
          },
          onDestinationSelected: (i) =>
              context.go(['/', '/cart', '/orders', '/profile'][i]),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.storefront_outlined), label: 'Discover'),
            NavigationDestination(
                icon: Icon(Icons.shopping_bag_outlined), label: 'Bag'),
            NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined), label: 'Orders'),
            NavigationDestination(
                icon: Icon(Icons.person_outline), label: 'Account')
          ]));
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
            const Icon(Icons.cloud_off, size: 44),
            const SizedBox(height: 16),
            Text(errorText(error), textAlign: TextAlign.center),
            TextButton(onPressed: retry, child: const Text('Try again'))
          ])));
}

class Empty extends StatelessWidget {
  final String text;
  const Empty(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(32),
      child: Center(child: Text(text, textAlign: TextAlign.center)));
}

class RemoteList extends ConsumerStatefulWidget {
  final String title;
  final Future<List<Json>> Function(int) load;
  final Widget Function(Json, VoidCallback) item;
  final List<Widget> header;
  final String? watch;
  final Widget? floatingBottom;
  const RemoteList(
      {required this.title,
      required this.load,
      required this.item,
      this.header = const [],
      this.watch,
      this.floatingBottom,
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
  RealtimeChannel? channel;
  @override
  void initState() {
    super.initState();
    load(true);
    if (widget.watch != null) {
      channel =
          ref.read(repositoryProvider).watch(widget.watch!, () => load(true));
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
      });
    } catch (e) {
      if (mounted && ticket == request) setState(() => error = e);
    } finally {
      if (mounted && ticket == request) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    if (channel != null) {
      ref.read(repositoryProvider).client.removeChannel(channel!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageFrame(widget.title,
      floatingBottom: widget.floatingBottom,
      child: RefreshIndicator(
          onRefresh: () => load(true),
          child: ListView(
              padding: EdgeInsets.fromLTRB(
                  20, 20, 20, widget.floatingBottom != null ? 100 : 20),
              children: [
            ...widget.header,
            if (busy) const LinearProgressIndicator(),
            if (error != null) Failure(error!, () => load(true)),
            if (!busy && data.isEmpty && error == null)
              const Empty('Nothing here yet.'),
            for (final row in data) widget.item(row, () => load(true)),
            if (more && !busy && data.isNotEmpty)
              TextButton(
                  onPressed: () => load(false), child: const Text('Load more'))
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
                      child: FilledButton(
                          onPressed: () => context.go('/login'),
                          child: const Text('Sign in'))));
            }
            if (!roles.contains(account.role)) {
              return const Scaffold(
                  body: Empty(
                      'This workspace is not available to your account.'));
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
  const Field(this.controller, this.label,
      {this.secret = false,
      this.requiredValue = true,
      this.keyboard,
      this.lines = 1,
      super.key});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
          controller: controller,
          obscureText: secret,
          maxLines: lines,
          keyboardType: keyboard,
          decoration: InputDecoration(labelText: label),
          validator: (v) => requiredValue && (v == null || v.trim().isEmpty)
              ? 'Required'
              : null));
}

class Photo extends StatelessWidget {
  final String? url;
  final double height;
  const Photo(this.url, {this.height = 150, super.key});
  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: url == null
          ? Container(
              height: height,
              color: const Color(0xFFE0F2FE),
              child: const Center(
                  child: Icon(Icons.storefront,
                      size: 44, color: Color(0xFF0EA5E9))))
          : Image.network(url!,
              height: height,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (a, b, c) => SizedBox(
                  height: height,
                  child: const Icon(Icons.image_not_supported_outlined))));
}
