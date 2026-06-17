import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/services/account_deletion_service.dart';
import '../../../../core/theme/app_colors.dart';

/// Irreversible account deletion. Reached from Settings (not buried). The user
/// reads exactly what is destroyed vs preserved, types DELETE to confirm, and
/// the final button initiates the permanent purge.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _confirm = TextEditingController();
  bool _deleting = false;

  static const _confirmWord = 'DELETE';

  bool get _canDelete =>
      _confirm.text.trim().toUpperCase() == _confirmWord && !_deleting;

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (!_canDelete) return;
    HapticFeedback.heavyImpact();
    setState(() => _deleting = true);

    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    final outcome =
        await ref.read(accountDeletionServiceProvider).deleteAccount();

    if (!mounted) return;

    // The session is gone and local data is wiped — leave for /auth and make
    // the dead session unreachable. The router's redirect guard reinforces this.
    router.go('/auth');
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          outcome.localWiped
              ? 'Your account and data have been permanently deleted.'
              : 'Signed out. Some data could not be removed — please retry.',
          style: GoogleFonts.inter(color: AppColors.textPrimary),
        ),
        backgroundColor: AppColors.bgSurface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        title: Text(
          'Delete account',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: AppColors.textPrimary,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: AbsorbPointer(
        absorbing: _deleting,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.delete_forever_rounded,
                  color: AppColors.error, size: 26),
            ),
            const SizedBox(height: 16),
            Text(
              'This is permanent',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Deleting your account cannot be undone. Once you confirm, your '
              'data will be permanently deleted — there is no recovery.',
              style: GoogleFonts.inter(
                fontSize: 14.5,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),

            const _SectionCard(
              title: 'What will be permanently deleted',
              tone: AppColors.error,
              icon: Icons.remove_circle_outline_rounded,
              lines: [
                'Your sign-in account and profile on our servers.',
                'Any workout, routine, or preference data synced to the cloud.',
                'All workout history, routines, and custom exercises stored on '
                    'this device.',
              ],
            ),
            const SizedBox(height: 14),
            const _SectionCard(
              title: 'What stays yours',
              tone: AppColors.success,
              icon: Icons.check_circle_outline_rounded,
              lines: [
                'Any CSV files you exported to your phone (Downloads / Files) '
                    'are your property — they are never touched or removed.',
              ],
            ),

            const SizedBox(height: 26),
            Text(
              'Type $_confirmWord to confirm',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _confirm,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              cursorColor: AppColors.error,
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
              decoration: InputDecoration(
                hintText: _confirmWord,
                hintStyle: GoogleFonts.inter(
                    // placeholder shows the literal word to type → must stay
                    // readable; textGhost (~4.9:1), not the disabled token.
                    color: AppColors.textGhost, letterSpacing: 1.5),
                filled: true,
                fillColor: AppColors.surfaceRaised,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.error, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _canDelete ? _delete : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  disabledBackgroundColor: AppColors.error.withValues(alpha: 0.18),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white.withValues(alpha: 0.5),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _deleting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        'Delete my account permanently',
                        style: GoogleFonts.inter(
                            fontSize: 15.5, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: _deleting ? null : () => context.pop(),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Color tone;
  final IconData icon;
  final List<String> lines;
  const _SectionCard({
    required this.title,
    required this.tone,
    required this.icon,
    required this.lines,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: tone),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 8),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textSecondary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      line,
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        height: 1.45,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
