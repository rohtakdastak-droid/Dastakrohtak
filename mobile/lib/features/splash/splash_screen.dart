import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../customer/profile_menu.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController entry = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800))
    ..forward();
  late final AnimationController pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2200))
    ..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    Future.wait([
      Future<void>.delayed(const Duration(milliseconds: 2400)),
      ref.read(accountProvider.future).timeout(const Duration(seconds: 6)).then<Object?>((a) => a, onError: (Object _) => null),
    ]).then((results) {
      final account = results[1] as Account?;
      if (!mounted) return;
      context.go(account != null && account.needsDetails
          ? '/complete-profile'
          : workspaceRoute(account?.role ?? 'customer'));
    });
  }

  @override
  void dispose() {
    entry.dispose();
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Container(
            decoration: const BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0EA5E9), Color(0xFF0369A1)])),
            child: SafeArea(
                child: Stack(children: [
              // Decorative blurred blobs
              Positioned(
                  top: -60,
                  right: -40,
                  child: _blob(220, Colors.white.withValues(alpha: 0.08))),
              Positioned(
                  bottom: -40,
                  left: -40,
                  child: _blob(260, Colors.white.withValues(alpha: 0.06))),
              Center(
                  child: AnimatedBuilder(
                      animation: entry,
                      builder: (c, _) {
                        final crownT = Curves.easeOutBack
                            .transform((entry.value * 1.5).clamp(0.0, 1.0));
                        final logoT = Curves.easeOutCubic.transform(
                            ((entry.value - 0.25) * 1.6).clamp(0.0, 1.0));
                        final taglineT = Curves.easeOut.transform(
                            ((entry.value - 0.55) * 2.2).clamp(0.0, 1.0));
                        return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ScaleTransition(
                                  scale: Tween(begin: 1.0, end: 1.08)
                                      .animate(pulse),
                                  child: Transform.translate(
                                      offset: Offset(0, (1 - crownT) * -40),
                                      child: Opacity(
                                          opacity: crownT,
                                          child: Container(
                                              width: 128,
                                              height: 128,
                                              decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(32),
                                                  boxShadow: [
                                                    BoxShadow(
                                                        color: Colors.black
                                                            .withValues(alpha: 0.22),
                                                        blurRadius: 28,
                                                        offset:
                                                            const Offset(0, 12))
                                                  ]),
                                              child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(32),
                                                  child: Image.asset(
                                                      'assets/logo.png',
                                                      width: 128,
                                                      height: 128,
                                                      fit: BoxFit.cover)))))),
                              const SizedBox(height: 24),
                              Opacity(
                                  opacity: logoT,
                                  child: Transform.translate(
                                      offset: Offset(0, (1 - logoT) * 20),
                                      child: Text('Dastak',
                                          style: GoogleFonts.playfairDisplay(
                                              color: Colors.white,
                                              fontSize: 56,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 1,
                                              shadows: [
                                                Shadow(
                                                    color: Colors.black
                                                        .withValues(alpha: 0.25),
                                                    blurRadius: 18,
                                                    offset: const Offset(0, 4))
                                              ])))),
                              const SizedBox(height: 14),
                              Opacity(
                                  opacity: taglineT,
                                  child: Transform.translate(
                                      offset: Offset(0, (1 - taglineT) * 12),
                                      child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Container(
                                                width: 24,
                                                height: 1,
                                                color: Colors.white
                                                    .withValues(alpha: 0.6)),
                                            const SizedBox(width: 10),
                                            Text('Dil Se Ghar Tak',
                                                style: GoogleFonts.dancingScript(
                                                    color: Colors.white,
                                                    fontSize: 24,
                                                    fontWeight: FontWeight.w700,
                                                    fontStyle: FontStyle.italic,
                                                    letterSpacing: 0.3)),
                                            const SizedBox(width: 10),
                                            Container(
                                                width: 24,
                                                height: 1,
                                                color: Colors.white
                                                    .withValues(alpha: 0.6))
                                          ]))),
                              const SizedBox(height: 6),
                              Opacity(
                                  opacity: taglineT,
                                  child: Text(
                                      'LOCAL DELIVERY',
                                      style: GoogleFonts.poppins(
                                          color: Colors.white.withValues(alpha: 0.75),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 3.5))),
                              const SizedBox(height: 60),
                              Opacity(
                                  opacity: taglineT,
                                  child: const SizedBox(
                                      width: 32,
                                      height: 32,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          valueColor: AlwaysStoppedAnimation(
                                              Colors.white))))
                            ]);
                      }))
            ]))));
  }

  Widget _blob(double size, Color color) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}
