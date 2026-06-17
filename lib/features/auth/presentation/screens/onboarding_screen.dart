import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gymlog/core/services/profile_sync_service.dart';
import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/features/auth/presentation/providers/auth_provider.dart';
import 'package:gymlog/shared/widgets/ui/app_dialog.dart';
import 'package:gymlog/shared/widgets/ui/primary_button.dart';

/// [onboarding_screen.dart]
/// Purpose: First-launch welcome — captures the display name and persists it
/// locally + to the backend (queued/retried if offline). Shown once, right
/// after a user's first-ever Google sign-in. Dismissible only via a valid
/// submission — no back-button escape without a name.

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _nameController = TextEditingController();
  final _focusNode = FocusNode();
  bool _isLoading = false;

  bool get _isValid => _nameController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Pre-fill from the Google account (full_name, then name) if available.
    final user = ref.read(authProvider);
    final meta = user?.userMetadata;
    final googleName = (meta?['full_name'] ?? meta?['name']) as String?;
    if (googleName != null && googleName.trim().isNotEmpty) {
      _nameController.text = googleName.trim();
    }
    // Live-update the primary button's enabled state as they type.
    _nameController.addListener(() => setState(() {}));
    // Auto-focus the field.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Visible escape hatch: signs the user out and returns to auth. Warns
  /// (don't silently discard) if they had typed a name. The system back gesture
  /// stays blocked (PopScope) so an accidental swipe can't lose the name — this
  /// explicit Cancel is the deliberate way out.
  Future<void> _cancel() async {
    if (_isLoading) return;
    if (_nameController.text.trim().isNotEmpty) {
      final discard = await showAppConfirmDialog(
        context: context,
        title: 'Cancel setup?',
        message: "The name you entered won't be saved. You'll be signed out "
            'and returned to the start.',
        confirmLabel: 'Sign Out',
        cancelLabel: 'Keep Editing',
        isDestructive: true,
      );
      if (!discard) return;
    }
    await ref.read(authRepositoryProvider).signOut();
    // The redirect guard lets /onboarding run regardless of auth, so navigate
    // explicitly — signing out alone won't move us off this screen.
    if (mounted) context.go('/auth');
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final user = ref.read(authProvider);
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      // Local write is instant; the remote push is queued + retried and never
      // blocks entry into the app.
      await ref.read(profileSyncProvider).submitDisplayName(
            userId: user.id,
            email: user.email ?? '',
            name: name,
          );
      if (mounted) context.go('/');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A welcome, not a toll booth — but there's no escape without a name.
    // canPop:false blocks the system back gesture until they submit.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bgBase,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _isLoading ? null : _cancel,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(48, 44),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.arrow_back_rounded,
                            size: 18, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          'Cancel',
                          style: GoogleFonts.inter(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'Welcome to GymLog',
                  style: GoogleFonts.inter(
                    // Teal accent text on the canvas (~8.4:1, passes AA).
                    color: AppColors.accentText,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'What should we\ncall you?',
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This is how you\'ll show up across GymLog — and it '
                  'follows you to every device.',
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _nameController,
                  focusNode: _focusNode,
                  maxLength: 40,
                  cursorColor: AppColors.accentPrimary,
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: 'Your name',
                    counterText: '',
                    hintStyle: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 18,
                    ),
                  ),
                ),
                const Spacer(),
                PrimaryButton(
                  label: 'Get Started',
                  // Enabled only on valid input; spinner while saving.
                  onPressed: _isValid && !_isLoading ? _submit : null,
                  isLoading: _isLoading,
                  icon: Icons.arrow_forward_rounded,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
