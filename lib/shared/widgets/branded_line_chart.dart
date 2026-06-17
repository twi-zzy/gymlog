import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/features/routines/presentation/widgets/routine_detail_styles.dart';

/// One data point on a [BrandedLineChart].
class ChartPoint {
  final DateTime date;
  final double value;
  const ChartPoint(this.date, this.value);
}

/// THE app chart. Routine Detail, Exercise Detail and Profile all render
/// through this single component so curve behavior, dot styling, axis
/// formatting, touch handling and empty states are pixel-identical.
///
/// Interaction model (Hevy-benchmarked, per design memory): no floating
/// tooltip box — touching a point updates the value+date header above the
/// plot. The latest point is emphasized with a ringed dot. Data changes
/// animate implicitly.
class BrandedLineChart extends StatefulWidget {
  final List<ChartPoint> data;

  /// Formats the header value ("12,450 kg", "128 min").
  final String Function(double value) valueFormatter;

  /// Formats Y-axis labels (compact, unitless — the section title owns
  /// the unit).
  final String Function(double value) axisFormatter;

  /// Formats the header date ("Jun 8" / "week of Jun 8").
  final String Function(DateTime date) dateFormatter;

  final String emptyTitle;
  final String emptySubtitle;
  final double height;

  BrandedLineChart({
    super.key,
    required this.data,
    required this.valueFormatter,
    String Function(double value)? axisFormatter,
    String Function(DateTime date)? dateFormatter,
    this.emptyTitle = 'No data yet',
    this.emptySubtitle = 'Finish a workout to see your trend',
    this.height = 180,
  })  : axisFormatter = axisFormatter ?? defaultAxisFormat,
        dateFormatter = dateFormatter ?? ((d) => DateFormat('MMM d').format(d));

  /// Compact axis labels with no float noise: 850 → "850", 3000 → "3k",
  /// 9000 → "9k" (never "9.0k"), 12500 → "12.5k". One rule for every
  /// chart in the app — axis language must not differ between screens.
  /// Public (not underscored) so the regression test can pin the contract.
  static String defaultAxisFormat(double v) {
    if (v >= 1000) {
      final k = v / 1000;
      return k == k.truncateToDouble()
          ? '${k.toInt()}k'
          : '${k.toStringAsFixed(1)}k';
    }
    return v.toInt().toString();
  }

  @override
  State<BrandedLineChart> createState() => _BrandedLineChartState();
}

class _BrandedLineChartState extends State<BrandedLineChart> {
  int? _touchedIndex;

  double _niceInterval(double maxV) {
    if (maxV <= 0) return 1;
    final raw = maxV / 3;
    final magnitude = raw <= 10
        ? 5.0
        : raw <= 100
            ? 25.0
            : raw <= 500
                ? 100.0
                : raw <= 1500
                    ? 500.0
                    : 1000.0;
    return (raw / magnitude).ceil() * magnitude;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (data.isEmpty) return _empty();

    final maxV =
        data.map((s) => s.value).fold<double>(0, (a, b) => a > b ? a : b);
    final interval = _niceInterval(maxV);
    final maxY =
        maxV <= 0 ? interval : ((maxV * 1.1) / interval).ceil() * interval;

    final n = data.length;
    final selIndex =
        (_touchedIndex == null || _touchedIndex! >= n) ? n - 1 : _touchedIndex!;
    final sel = data[selIndex];

    final spots = [
      for (var i = 0; i < n; i++) FlSpot(i.toDouble(), data[i].value)
    ];

    // Intentional X-label density: first, last, and ~2 between.
    final labelStep = n <= 4 ? 1 : (n / 4).ceil();

    // Average reference line — only meaningful with 3+ points AND visible
    // spread. On a flat series avg == every value, so the dashed line would
    // draw directly on top of the data line and trail past the last point
    // with a stray "avg" caption crowding the selected dot.
    final minV = data
        .map((s) => s.value)
        .fold<double>(double.infinity, (a, b) => a < b ? a : b);
    final bool hasSpread = (maxV - minV) > 0.001;
    final double? avg = (n >= 3 && hasSpread)
        ? data.map((s) => s.value).reduce((a, b) => a + b) / n
        : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
      decoration: BoxDecoration(
        gradient: RDStyles.cardGradient,
        borderRadius: BorderRadius.circular(20),
        border: RDStyles.hairlineBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Value header — updates on touch, no floating tooltip box.
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(widget.valueFormatter(sel.value),
                    style: RDStyles.chartValue),
                const SizedBox(width: 8),
                Text(widget.dateFormatter(sel.date), style: RDStyles.chartDate),
              ],
            ),
          ),
          SizedBox(
            height: widget.height,
            child: LineChart(
              // Reduce-motion: render the chart instantly, no entry tween.
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              LineChartData(
                minY: 0,
                maxY: maxY,
                minX: -0.35,
                maxX: (n - 1) + 0.35,
                clipData: const FlClipData.none(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: interval,
                  getDrawingHorizontalLine: (v) =>
                      FlLine(color: RDStyles.hairline, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: interval,
                      getTitlesWidget: (v, m) => (v <= 0 || v > maxY)
                          ? const SizedBox.shrink()
                          : SideTitleWidget(
                              axisSide: m.axisSide,
                              space: 8,
                              child: Text(widget.axisFormatter(v),
                                  style: RDStyles.axis),
                            ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: 1,
                      getTitlesWidget: (v, m) {
                        if (v != v.roundToDouble()) {
                          return const SizedBox.shrink();
                        }
                        final i = v.toInt();
                        if (i < 0 || i >= n) return const SizedBox.shrink();
                        final isEdge = i == 0 || i == n - 1;
                        if (!isEdge && i % labelStep != 0) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          axisSide: m.axisSide,
                          space: 8,
                          child: Text(widget.dateFormatter(data[i].date),
                              style: RDStyles.axis),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  enabled: true,
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => Colors.transparent,
                    tooltipPadding: EdgeInsets.zero,
                    tooltipMargin: 0,
                    getTooltipItems: (s) => s.map((_) => null).toList(),
                  ),
                  getTouchedSpotIndicator: (bar, idx) => idx
                      .map((i) => TouchedSpotIndicatorData(
                            FlLine(
                              color: AppColors.accentPrimary
                                  .withValues(alpha: 0.25),
                              strokeWidth: 1,
                            ),
                            FlDotData(
                              show: true,
                              getDotPainter: (s, p, b, ix) =>
                                  FlDotCirclePainter(
                                radius: 5.5,
                                color: AppColors.accentPrimary,
                                strokeWidth: 2.5,
                                strokeColor: Colors.white,
                              ),
                            ),
                          ))
                      .toList(),
                  touchCallback: (e, resp) {
                    if (resp?.lineBarSpots?.isNotEmpty ?? false) {
                      setState(() =>
                          _touchedIndex = resp!.lineBarSpots!.first.spotIndex);
                    }
                  },
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: false,
                    color: AppColors.accentPrimary,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, pct, bar, i) {
                        // Only the SELECTED point (defaults to latest, moves
                        // on tap) gets the emphasized ringed dot — no
                        // permanent white ring decorating the last point.
                        final isSelected = i == selIndex;
                        return FlDotCirclePainter(
                          radius: isSelected ? 5.5 : 3,
                          color: AppColors.accentPrimary,
                          strokeWidth: isSelected ? 2.5 : 0,
                          strokeColor: Colors.white,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.accentPrimary.withValues(alpha: 0.30),
                          AppColors.accentPrimary.withValues(alpha: 0.02),
                        ],
                      ),
                    ),
                  ),
                ],
                // Dashed average line — a quiet reference the eye can read
                // each point against. Hidden for trivial 1-2 point series.
                extraLinesData: ExtraLinesData(
                  horizontalLines: avg == null
                      ? const []
                      : [
                          HorizontalLine(
                            y: avg,
                            color:
                                AppColors.textSecondary.withValues(alpha: 0.30),
                            strokeWidth: 1,
                            dashArray: const [4, 4],
                            label: HorizontalLineLabel(
                              show: true,
                              alignment: Alignment.topRight,
                              padding:
                                  const EdgeInsets.only(right: 4, bottom: 2),
                              style: RDStyles.axis,
                              labelResolver: (_) => 'avg',
                            ),
                          ),
                        ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() => Container(
        height: 150,
        decoration: BoxDecoration(
          gradient: RDStyles.cardGradient,
          borderRadius: BorderRadius.circular(20),
          border: RDStyles.hairlineBorder,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 34,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final h in const [0.40, 0.65, 0.50, 0.80, 0.95])
                    Container(
                      width: 6,
                      height: 34 * h,
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF3A2A55), Color(0xFF1A1A1D)],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(widget.emptyTitle, style: RDStyles.emptyTitle),
            const SizedBox(height: 3),
            Text(widget.emptySubtitle, style: RDStyles.emptySub),
          ],
        ),
      );
}
