import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gymlog/core/database/database.dart';
import 'package:gymlog/core/providers/database_provider.dart';
import 'package:gymlog/core/providers/premium_provider.dart';
import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/core/database/daos/routines_dao.dart';
import 'package:gymlog/features/auth/presentation/providers/auth_provider.dart';
import 'package:gymlog/shared/widgets/premium_paywall.dart';
import '../widgets/routine_detail_styles.dart';

/// One slot in a template. [name] is the EXACT canonical Exercise Library
/// name (verified to exist), so it is both the display label and the import
/// key — there is no fuzzy guessing and no mismatch between what the card
/// shows and what gets added. [reps] seeds the routine's per-set target.
class _TemplateSlot {
  final String name;
  final int sets;
  final int reps;

  const _TemplateSlot(this.name, {this.sets = 3, this.reps = 10});
}

/// Difficulty tiers — drive the colored pill on each card.
enum _Level { beginner, intermediate, advanced }

class _RoutineTemplate {
  final String name;

  /// Programming family used to group the catalog (PPL, Upper/Lower, …).
  final String category;
  final _Level level;

  /// Target muscle groups, human-readable and scannable.
  final String focus;
  final String description;
  final Color accent;
  final List<_TemplateSlot> slots;

  const _RoutineTemplate({
    required this.name,
    required this.category,
    required this.level,
    required this.focus,
    required this.description,
    required this.accent,
    required this.slots,
  });

  int get totalSets => slots.fold(0, (a, s) => a + s.sets);

  /// Honest estimate: ~2.8 min per working set (work + rest) + warm-up,
  /// rounded to the nearest 5 minutes.
  int get estMinutes => (((totalSets * 2.8) + 8) / 5).round() * 5;

  String get levelLabel => switch (level) {
        _Level.beginner => 'Beginner',
        _Level.intermediate => 'Intermediate',
        _Level.advanced => 'Advanced',
      };

  Color get levelColor => switch (level) {
        _Level.beginner => const Color(0xFF34C759), // green
        _Level.intermediate => const Color(0xFF00C4A0), // lavender
        _Level.advanced => const Color(0xFFE0A422), // amber (intensity)
      };
}

// Category accents (kept inside the brand's purple family for cohesion).
const _cPPL = Color(0xFF00C4A0);
const _cUL = Color(0xFF00C4A0);
const _cFull = Color(0xFFCBB2FF);
const _cPower = Color(0xFF00C4A0);
const _cBro = Color(0xFF00C4A0);

/// Display order for the grouped sections.
const _categoryOrder = <String>[
  'Push · Pull · Legs',
  'Upper · Lower',
  'Powerbuilding',
  'Bro Split',
  'Full Body',
];

/// The curated catalog. EVERY exercise name below is an exact entry in the
/// bundled Exercise Library (assets/db/exercises.json), audited 2026-06-13 —
/// no broken references, no fuzzy fallbacks resolving to the wrong movement.
const _templates = <_RoutineTemplate>[
  // ── Push / Pull / Legs ───────────────────────────────────────────────────
  _RoutineTemplate(
    name: 'Push Day',
    category: 'Push · Pull · Legs',
    level: _Level.intermediate,
    focus: 'Chest · Shoulders · Triceps',
    description: 'The classic pressing session — heavy bench first, then '
        'shoulders and triceps to finish.',
    accent: _cPPL,
    slots: [
      _TemplateSlot('Bench Press (Barbell)', sets: 4, reps: 6),
      _TemplateSlot('Smith Standing Military Press', sets: 3, reps: 8),
      _TemplateSlot('Incline Bench Press (Barbell)', sets: 3, reps: 10),
      _TemplateSlot('Lateral Raise (Cable)', sets: 3, reps: 15),
      _TemplateSlot('Chest Dip', sets: 3, reps: 10),
      _TemplateSlot('Cable Pushdown', sets: 3, reps: 12),
    ],
  ),
  _RoutineTemplate(
    name: 'Pull Day',
    category: 'Push · Pull · Legs',
    level: _Level.intermediate,
    focus: 'Back · Biceps · Rear Delts',
    description: 'Width and thickness — pull from the floor, a vertical pull, '
        'a row, then arms.',
    accent: _cPPL,
    slots: [
      _TemplateSlot('Deadlift (Barbell)', sets: 3, reps: 5),
      _TemplateSlot('Pull Up', sets: 4, reps: 8),
      _TemplateSlot('Bent Over Row (Barbell)', sets: 3, reps: 8),
      _TemplateSlot('Cable Pulldown', sets: 3, reps: 12),
      _TemplateSlot('Reverse Fly (Dumbbell)', sets: 3, reps: 15),
      _TemplateSlot('Barbell Curl', sets: 3, reps: 10),
    ],
  ),
  _RoutineTemplate(
    name: 'Leg Day',
    category: 'Push · Pull · Legs',
    level: _Level.intermediate,
    focus: 'Quads · Hamstrings · Calves',
    description: 'Squat-centric lower session with a hip-hinge for the '
        'hamstrings and dedicated calf work.',
    accent: _cPPL,
    slots: [
      _TemplateSlot('Barbell Full Squat', sets: 4, reps: 6),
      _TemplateSlot('Barbell Straight Leg Deadlift', sets: 3, reps: 8),
      _TemplateSlot('Sled 45° Leg Press', sets: 3, reps: 12),
      _TemplateSlot('Lying Leg Curl', sets: 3, reps: 12),
      _TemplateSlot('Standing Calf Raise (Barbell)', sets: 4, reps: 15),
    ],
  ),
  _RoutineTemplate(
    name: 'Push Day · Volume',
    category: 'Push · Pull · Legs',
    level: _Level.advanced,
    focus: 'Chest · Shoulders · Triceps',
    description: 'A higher-volume hypertrophy push — dumbbells and cables for '
        'time under tension, lighter loads, tighter rest.',
    accent: _cPPL,
    slots: [
      _TemplateSlot('Bench Press (Dumbbell)', sets: 4, reps: 10),
      _TemplateSlot('Incline Bench Press (Barbell)', sets: 3, reps: 10),
      _TemplateSlot('Lever Shoulder Press', sets: 3, reps: 10),
      _TemplateSlot('Dumbbell Fly', sets: 3, reps: 12),
      _TemplateSlot('Lateral Raise (Cable)', sets: 4, reps: 15),
      _TemplateSlot('Barbell Lying Triceps Extension', sets: 3, reps: 12),
      _TemplateSlot('Cable Pushdown', sets: 3, reps: 15),
    ],
  ),
  _RoutineTemplate(
    name: 'Pull Day · Volume',
    category: 'Push · Pull · Legs',
    level: _Level.advanced,
    focus: 'Back · Biceps · Rear Delts',
    description: 'Back-building volume — pulldowns and rows for the lats and '
        'mid-back, then traps, rear delts and biceps.',
    accent: _cPPL,
    slots: [
      _TemplateSlot('Cable Pulldown', sets: 4, reps: 12),
      _TemplateSlot('Cable Low Seated Row', sets: 4, reps: 10),
      _TemplateSlot('Bent Over Row (Dumbbell)', sets: 3, reps: 10),
      _TemplateSlot('Shrug (Barbell)', sets: 3, reps: 12),
      _TemplateSlot('Reverse Fly (Dumbbell)', sets: 3, reps: 15),
      _TemplateSlot('Bicep Curl (Dumbbell)', sets: 3, reps: 12),
      _TemplateSlot('Hammer Curl (Dumbbell)', sets: 3, reps: 12),
    ],
  ),
  _RoutineTemplate(
    name: 'Leg Day · Volume',
    category: 'Push · Pull · Legs',
    level: _Level.advanced,
    focus: 'Quads · Hamstrings · Glutes',
    description: 'Quad and glute hypertrophy — front squats, presses, '
        'extensions and a rope pull-through for the hips.',
    accent: _cPPL,
    slots: [
      _TemplateSlot('Front Squat (Barbell)', sets: 4, reps: 8),
      _TemplateSlot('Sled 45° Leg Press', sets: 4, reps: 12),
      _TemplateSlot('Leg Extension (Machine)', sets: 4, reps: 15),
      _TemplateSlot('Seated Leg Curl (Machine)', sets: 4, reps: 12),
      _TemplateSlot('Cable Pull Through', sets: 3, reps: 12),
      _TemplateSlot('Seated Calf Raise (Machine)', sets: 4, reps: 20),
    ],
  ),
  // ── Upper / Lower ─────────────────────────────────────────────────────────
  _RoutineTemplate(
    name: 'Upper Body',
    category: 'Upper · Lower',
    level: _Level.intermediate,
    focus: 'Chest · Back · Shoulders · Arms',
    description: 'Everything above the waist in one efficient session — '
        'built for an upper/lower split.',
    accent: _cUL,
    slots: [
      _TemplateSlot('Bench Press (Barbell)', sets: 4, reps: 6),
      _TemplateSlot('Bent Over Row (Barbell)', sets: 4, reps: 8),
      _TemplateSlot('Smith Standing Military Press', sets: 3, reps: 8),
      _TemplateSlot('Cable Pulldown', sets: 3, reps: 10),
      _TemplateSlot('Bicep Curl (Dumbbell)', sets: 3, reps: 12),
      _TemplateSlot('Cable Pushdown', sets: 3, reps: 12),
    ],
  ),
  _RoutineTemplate(
    name: 'Lower Body',
    category: 'Upper · Lower',
    level: _Level.intermediate,
    focus: 'Quads · Hamstrings · Calves',
    description: 'The other half of the upper/lower split — squat, hinge and '
        'single-leg work, capped with calves.',
    accent: _cUL,
    slots: [
      _TemplateSlot('Barbell Full Squat', sets: 4, reps: 6),
      _TemplateSlot('Barbell Straight Leg Deadlift', sets: 3, reps: 8),
      _TemplateSlot('Lunge (Dumbbell)', sets: 3, reps: 10),
      _TemplateSlot('Leg Extension (Machine)', sets: 3, reps: 15),
      _TemplateSlot('Seated Calf Raise (Machine)', sets: 4, reps: 15),
    ],
  ),
  // ── Powerbuilding ──────────────────────────────────────────────────────────
  _RoutineTemplate(
    name: 'Upper Power',
    category: 'Powerbuilding',
    level: _Level.advanced,
    focus: 'Strength · Chest · Back · Shoulders',
    description: 'Heavy upper-body strength — low-rep presses and rows for '
        'force, a little hypertrophy work to finish.',
    accent: _cPower,
    slots: [
      _TemplateSlot('Bench Press (Barbell)', sets: 5, reps: 5),
      _TemplateSlot('Bent Over Row (Barbell)', sets: 5, reps: 5),
      _TemplateSlot('Smith Standing Military Press', sets: 4, reps: 6),
      _TemplateSlot('Pull Up', sets: 3, reps: 8),
      _TemplateSlot('Barbell Curl', sets: 3, reps: 10),
      _TemplateSlot('Tricep Pushdown With Bar', sets: 3, reps: 12),
    ],
  ),
  _RoutineTemplate(
    name: 'Lower Power',
    category: 'Powerbuilding',
    level: _Level.advanced,
    focus: 'Strength · Quads · Posterior Chain',
    description: 'Squat and deadlift strength work, then leg press and good '
        'mornings to build the posterior chain.',
    accent: _cPower,
    slots: [
      _TemplateSlot('Barbell Full Squat', sets: 5, reps: 5),
      _TemplateSlot('Deadlift (Barbell)', sets: 3, reps: 5),
      _TemplateSlot('Sled 45° Leg Press', sets: 3, reps: 10),
      _TemplateSlot('Good Morning (Barbell)', sets: 3, reps: 10),
      _TemplateSlot('Standing Calf Raise (Barbell)', sets: 4, reps: 12),
    ],
  ),
  // ── Bro Split ────────────────────────────────────────────────────────────
  _RoutineTemplate(
    name: 'Chest & Triceps',
    category: 'Bro Split',
    level: _Level.intermediate,
    focus: 'Chest · Triceps',
    description: 'A dedicated chest day with triceps along for the ride — '
        'press, incline, fly, then push the arms.',
    accent: _cBro,
    slots: [
      _TemplateSlot('Bench Press (Barbell)', sets: 4, reps: 8),
      _TemplateSlot('Incline Bench Press (Barbell)', sets: 3, reps: 10),
      _TemplateSlot('Dumbbell Fly', sets: 3, reps: 12),
      _TemplateSlot('Chest Dip', sets: 3, reps: 10),
      _TemplateSlot('Barbell Lying Triceps Extension', sets: 3, reps: 12),
      _TemplateSlot('Cable Pushdown', sets: 3, reps: 15),
    ],
  ),
  _RoutineTemplate(
    name: 'Back & Biceps',
    category: 'Bro Split',
    level: _Level.intermediate,
    focus: 'Back · Biceps',
    description: 'Pull-focused day — a heavy deadlift, vertical and horizontal '
        'pulls, then curls to cap it.',
    accent: _cBro,
    slots: [
      _TemplateSlot('Deadlift (Barbell)', sets: 3, reps: 5),
      _TemplateSlot('Pull Up', sets: 4, reps: 8),
      _TemplateSlot('Cable Low Seated Row', sets: 3, reps: 10),
      _TemplateSlot('Cable Pulldown', sets: 3, reps: 12),
      _TemplateSlot('Barbell Curl', sets: 3, reps: 10),
      _TemplateSlot('Incline Dumbbell Curl', sets: 3, reps: 12),
    ],
  ),
  _RoutineTemplate(
    name: 'Shoulders & Core',
    category: 'Bro Split',
    level: _Level.intermediate,
    focus: 'Shoulders · Core',
    description: 'Build round delts from every angle, then brace the core '
        'with hanging and anti-extension work.',
    accent: _cBro,
    slots: [
      _TemplateSlot('Smith Standing Military Press', sets: 4, reps: 8),
      _TemplateSlot('Dumbbell Push Press', sets: 3, reps: 8),
      _TemplateSlot('Lateral Raise (Cable)', sets: 4, reps: 15),
      _TemplateSlot('Reverse Fly (Dumbbell)', sets: 3, reps: 15),
      _TemplateSlot('Upright Row (Barbell)', sets: 3, reps: 12),
      _TemplateSlot('Hanging Pike', sets: 3, reps: 15),
      _TemplateSlot('Weighted Front Plank', sets: 3, reps: 40),
    ],
  ),
  _RoutineTemplate(
    name: 'Arm Day',
    category: 'Bro Split',
    level: _Level.beginner,
    focus: 'Biceps · Triceps',
    description: 'Pure arms — supersets of curls and extensions for a serious '
        'pump. Short, focused, effective.',
    accent: _cBro,
    slots: [
      _TemplateSlot('Barbell Curl', sets: 4, reps: 10),
      _TemplateSlot('Cable Pushdown', sets: 4, reps: 12),
      _TemplateSlot('Hammer Curl (Dumbbell)', sets: 3, reps: 12),
      _TemplateSlot('Barbell Lying Triceps Extension', sets: 3, reps: 12),
      _TemplateSlot('Incline Dumbbell Curl', sets: 3, reps: 15),
      _TemplateSlot('EZ Bar Standing French Press', sets: 3, reps: 12),
    ],
  ),
  // ── Full Body ──────────────────────────────────────────────────────────────
  _RoutineTemplate(
    name: 'Full Body Express',
    category: 'Full Body',
    level: _Level.beginner,
    focus: 'Total Body · 45 min',
    description: 'Three big compounds and two finishers — for the days when '
        'time is the limiting factor.',
    accent: _cFull,
    slots: [
      _TemplateSlot('Barbell Full Squat', sets: 3, reps: 8),
      _TemplateSlot('Bench Press (Barbell)', sets: 3, reps: 8),
      _TemplateSlot('Bent Over Row (Barbell)', sets: 3, reps: 8),
      _TemplateSlot('Weighted Front Plank', sets: 2, reps: 30),
      _TemplateSlot('Bicep Curl (Dumbbell)', sets: 2, reps: 12),
    ],
  ),
  _RoutineTemplate(
    name: 'Beginner Full Body A',
    category: 'Full Body',
    level: _Level.beginner,
    focus: 'Total Body · Foundations',
    description: 'Day A of a simple 3×/week start — squat and bench focus, '
        'one pull, a press, and a plank.',
    accent: _cFull,
    slots: [
      _TemplateSlot('Barbell Full Squat', sets: 3, reps: 8),
      _TemplateSlot('Bench Press (Barbell)', sets: 3, reps: 8),
      _TemplateSlot('Cable Pulldown', sets: 3, reps: 10),
      _TemplateSlot('Smith Standing Military Press', sets: 2, reps: 10),
      _TemplateSlot('Weighted Front Plank', sets: 3, reps: 30),
    ],
  ),
  _RoutineTemplate(
    name: 'Beginner Full Body B',
    category: 'Full Body',
    level: _Level.beginner,
    focus: 'Total Body · Foundations',
    description: 'Day B of the 3×/week start — deadlift and dumbbell pressing '
        'balanced with a row and goblet squat.',
    accent: _cFull,
    slots: [
      _TemplateSlot('Deadlift (Barbell)', sets: 3, reps: 5),
      _TemplateSlot('Bench Press (Dumbbell)', sets: 3, reps: 10),
      _TemplateSlot('Cable Low Seated Row', sets: 3, reps: 10),
      _TemplateSlot('Goblet Squat', sets: 3, reps: 12),
      _TemplateSlot('Bicep Curl (Dumbbell)', sets: 2, reps: 12),
    ],
  ),
];

/// Explore — a curated catalog of premade routines, importable into the
/// user's library in one tap. Discovery and retention, not navigation.
class ExploreRoutinesScreen extends ConsumerStatefulWidget {
  const ExploreRoutinesScreen({super.key});

  @override
  ConsumerState<ExploreRoutinesScreen> createState() =>
      _ExploreRoutinesScreenState();
}

class _ExploreRoutinesScreenState extends ConsumerState<ExploreRoutinesScreen> {
  final Set<String> _importing = {};
  final Set<String> _imported = {};

  Future<void> _import(_RoutineTemplate template) async {
    final user = ref.read(authProvider);
    if (user == null || _importing.contains(template.name)) return;

    // Free-tier routine cap — importing a template creates a routine, so it
    // counts against the limit exactly like manual creation does.
    final isPremium = ref.read(isPremiumProvider);
    final count =
        await ref.read(databaseProvider).routinesDao.countRoutinesForUser(user.id);
    if (isAtFreeRoutineLimit(isPremium: isPremium, routineCount: count)) {
      if (mounted) await showRoutineLimitUpsell(context);
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _importing.add(template.name));

    try {
      final db = ref.read(databaseProvider);

      // Resolve each slot by EXACT canonical name first (the names are audited
      // to exist), falling back to a substring match only for resilience
      // against a differently-versioned library. This is what fixes the old
      // bug where "pull-up" alphabetically resolved to "Assisted Pull-Up".
      final drafts = <RoutineDraftExercise>[];
      var missed = 0;
      for (final slot in template.slots) {
        final hits = await db.exercisesDao.searchExercises(slot.name);
        Exercise? match;
        for (final e in hits) {
          if (e.name.toLowerCase() == slot.name.toLowerCase()) {
            match = e;
            break;
          }
        }
        match ??= hits.isNotEmpty ? hits.first : null;

        if (match != null) {
          drafts.add(RoutineDraftExercise(
            exerciseId: match.id,
            defaultSets: slot.sets,
            defaultReps: slot.reps,
          ));
        } else {
          missed++;
        }
      }

      if (drafts.isEmpty) {
        _snack('Could not match these exercises in your library.');
        return;
      }

      await db.routinesDao.createRoutine(
        userId: user.id,
        name: template.name,
        exercises: drafts,
      );

      if (!mounted) return;
      setState(() => _imported.add(template.name));
      HapticFeedback.heavyImpact();
      _snack(missed == 0
          ? '"${template.name}" added to My Routines.'
          : '"${template.name}" added — $missed exercise${missed > 1 ? 's' : ''} not in your library were skipped.');
    } finally {
      if (mounted) setState(() => _importing.remove(template.name));
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(message, style: GoogleFonts.inter(color: AppColors.textPrimary)),
      backgroundColor: AppColors.bgSurface,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Group templates by category, preserving the curated section order.
    final byCategory = <String, List<_RoutineTemplate>>{};
    for (final t in _templates) {
      byCategory.putIfAbsent(t.category, () => []).add(t);
    }
    final sections = [
      for (final c in _categoryOrder)
        if (byCategory[c] != null) (c, byCategory[c]!),
    ];

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        scrolledUnderElevation: 0,
        titleSpacing: 0, // title hugs the back button on every sub-screen
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Explore',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            letterSpacing: -0.3,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 48),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              'Trainer-built programs, ready to train. Import one and make '
              'it yours.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          for (final (category, items) in sections) ...[
            _SectionHeader(label: category, count: items.length),
            for (final template in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _TemplateCard(
                  template: template,
                  importing: _importing.contains(template.name),
                  imported: _imported.contains(template.name),
                  onImport: () => _import(template),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  const _SectionHeader({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              // Was textSecondary @0.5α ≈ 2.3:1 — a hard WCAG AA fail. Full
              // textSecondary at 12px clears 4.5:1.
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final _RoutineTemplate template;
  final bool importing;
  final bool imported;
  final VoidCallback onImport;

  const _TemplateCard({
    required this.template,
    required this.importing,
    required this.imported,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    // Preview the first three exercises by their REAL library names.
    final preview = template.slots.take(3).map((s) => s.name).join(', ');
    final extra = template.slots.length - 3;

    return Container(
      decoration: BoxDecoration(
        gradient: RDStyles.cardGradient,
        borderRadius: BorderRadius.circular(12),
        border: RDStyles.hairlineBorder,
      ),
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: template.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  template.name[0],
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: template.accent,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.name,
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      template.focus,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Scannable metadata: difficulty · duration · exercises ─────
          // Wrap (not Row) so the chips reflow instead of overflowing on
          // narrow screens or at large system text scales.
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _LevelPill(label: template.levelLabel, color: template.levelColor),
              _MetaChip(
                  icon: Icons.schedule_rounded,
                  label: '~${template.estMinutes} min'),
              _MetaChip(
                  icon: Icons.fitness_center_rounded,
                  label: '${template.slots.length} exercises'),
            ],
          ),
          const SizedBox(height: 11),

          Text(
            template.description,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 13),
            child: Container(height: 1, color: RDStyles.hairline),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$preview${extra > 0 ? '  +$extra' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _ImportPill(
                  importing: importing,
                  imported: imported,
                  onTap: onImport,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelPill extends StatelessWidget {
  final String label;
  final Color color;
  const _LevelPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _ImportPill extends StatelessWidget {
  final bool importing;
  final bool imported;
  final VoidCallback onTap;

  const _ImportPill({
    required this.importing,
    required this.imported,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !imported && !importing,
      label: importing
          ? 'Adding routine'
          : imported
              ? 'Added to your routines'
              : 'Add this routine',
      excludeSemantics: true,
      child: Material(
      color: imported
          ? AppColors.success.withValues(alpha: 0.14)
          : AppColors.accentPrimary,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: imported || importing ? null : onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          child: importing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      imported ? Icons.check_rounded : Icons.download_rounded,
                      size: 15,
                      color: imported ? AppColors.success : Colors.white,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      imported ? 'Added' : 'Add',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: imported ? AppColors.success : Colors.white,
                      ),
                    ),
                  ],
                ),
        ),
      ),
      ),
    );
  }
}
