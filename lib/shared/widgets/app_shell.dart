import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../features/workout/presentation/providers/active_workout_provider.dart';
import '../../core/services/workout_draft_store.dart';
import '../../core/theme/app_colors.dart';
import 'active_workout_bar.dart';
import 'bottom_nav_bar.dart';

/// [app_shell.dart]
/// Purpose: High-Density Tracker - App shell with bottom nav
/// Mounts once after auth, so it's the natural place to offer to resume an
/// interrupted workout (a draft persisted by [WorkoutDraftStore]).

class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  const AppShell({required this.child, super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    // One-time, after first frame: offer to resume a crash-interrupted session.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOfferResume());
  }

  Future<void> _maybeOfferResume() async {
    // Don't interrupt if a session is somehow already live.
    if (!mounted || ref.read(activeWorkoutProvider) != null) return;
    final store = ref.read(workoutDraftStoreProvider);
    final draft = await store.load(); // null if none / older than 24h
    if (draft == null || !mounted) return;

    final mins = DateTime.now().difference(draft.startTime).inMinutes;
    final ago = mins < 1
        ? 'just now'
        : mins < 60
            ? '$mins min ago'
            : '${mins ~/ 60}h ${mins % 60}m ago';

    final resume = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // force an explicit choice
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSheet,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Resume workout?',
            style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        content: Text(
          'You have an unfinished workout started $ago. Resume where you left off?',
          style: GoogleFonts.inter(
              color: AppColors.textSecondary, fontSize: 14.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Discard',
                style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Resume',
                style: GoogleFonts.inter(
                    color: AppColors.accentText, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (resume == true) {
      ref.read(activeWorkoutProvider.notifier).resumeDraft(draft);
      context.push('/workout/active');
    } else {
      await store.clear(); // explicit decline → discard
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWorkoutActive = ref.watch(activeWorkoutProvider) != null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: widget.child,
          ),
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration:
                reduceMotion ? Duration.zero : const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeOutCubic,
            transitionBuilder: (child, animation) {
              return SizeTransition(
                sizeFactor: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 1.0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: isWorkoutActive
                ? const ActiveWorkoutBar(key: ValueKey('activeBar'))
                : const SizedBox.shrink(key: ValueKey('emptyBar')),
          ),
          const BottomNavBar(),
        ],
      ),
    );
  }
}
