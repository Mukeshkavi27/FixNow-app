import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/fixnow_admin_shell.dart';
import '../../../core/branches/branch_info.dart';
import '../../auth/domain/app_user.dart';
import '../../bookings/domain/booking.dart';
import '../domain/bill.dart';
import '../domain/review.dart';
import '../domain/technician_performance_analytics.dart';

class TechnicianPerformanceDashboard extends StatefulWidget {
  const TechnicianPerformanceDashboard({
    super.key,
    required this.technicians,
    required this.bookings,
    required this.bills,
    required this.reviews,
    required this.branches,
    this.lockedBranchId,
    this.title = 'Technician performance',
    this.subtitle = 'Revenue, job quality, ratings, and team rankings',
  });

  final List<AppUser> technicians;
  final List<Booking> bookings;
  final List<Bill> bills;
  final List<Review> reviews;
  final List<BranchInfo> branches;
  final String? lockedBranchId;
  final String title;
  final String subtitle;

  @override
  State<TechnicianPerformanceDashboard> createState() =>
      _TechnicianPerformanceDashboardState();
}

class _TechnicianPerformanceDashboardState
    extends State<TechnicianPerformanceDashboard> {
  String _branchFilter = 'all';

  @override
  void initState() {
    super.initState();
    _branchFilter = widget.lockedBranchId ?? 'all';
  }

  @override
  void didUpdateWidget(covariant TechnicianPerformanceDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lockedBranchId != widget.lockedBranchId) {
      _branchFilter = widget.lockedBranchId ?? 'all';
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedBranch = _branchFilter == 'all' ? null : _branchFilter;
    final analytics = TechnicianPerformanceAnalytics.calculate(
      technicians: widget.technicians,
      bookings: widget.bookings,
      bills: widget.bills,
      reviews: widget.reviews,
      branches: widget.branches,
      branchId: selectedBranch,
    );
    final showFilter =
        widget.lockedBranchId == null && widget.branches.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 12,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.subtitle,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
            if (showFilter)
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String>(
                  initialValue: _branchFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Performance branch',
                    prefixIcon: Icon(Icons.account_tree_outlined),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All branches'),
                    ),
                    for (final branch in widget.branches)
                      DropdownMenuItem(
                        value: branch.id,
                        child: Text(branch.name),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _branchFilter = value);
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        _PerformanceMetricGrid(analytics: analytics),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final top = _PerformancePanel(
              title: 'Top performers',
              subtitle: 'Highest composite performance score',
              child: _PerformerList(
                records: analytics.topPerformers,
                icon: Icons.emoji_events_outlined,
                color: AppTheme.instantGreen,
              ),
            );
            final lowest = _PerformancePanel(
              title: 'Lowest performers',
              subtitle: 'Team members needing coaching or support',
              child: _PerformerList(
                records: analytics.lowestPerformers,
                icon: Icons.trending_down_outlined,
                color: const Color(0xFFD95C2A),
              ),
            );
            return constraints.maxWidth >= 850
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: top),
                      const SizedBox(width: 18),
                      Expanded(child: lowest),
                    ],
                  )
                : Column(
                    children: [top, const SizedBox(height: 18), lowest],
                  );
          },
        ),
        const SizedBox(height: 18),
        _PerformancePanel(
          title: 'Technician leaderboard',
          subtitle:
              'Score combines completion (35%), rating (35%), satisfaction (20%), and revenue (10%)',
          child: analytics.leaderboard.isEmpty
              ? const _PerformanceEmpty('No technician activity yet')
              : _LeaderboardTable(records: analytics.leaderboard),
        ),
        const SizedBox(height: 18),
        _PerformancePanel(
          title: 'Branch ranking',
          subtitle: 'Performance comparison across the FixNow network',
          child: analytics.branchRanking.isEmpty
              ? const _PerformanceEmpty('No branch performance yet')
              : _BranchRankingList(records: analytics.branchRanking),
        ),
      ],
    );
  }
}

class _PerformanceMetricGrid extends StatelessWidget {
  const _PerformanceMetricGrid({required this.analytics});
  final TechnicianPerformanceAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _PerformanceMetric(
        'Technician revenue',
        _money(analytics.totalRevenue),
        Icons.currency_rupee,
        AppTheme.primary,
      ),
      _PerformanceMetric(
        'Jobs completed',
        '${analytics.totalCompletedJobs}',
        Icons.task_alt_outlined,
        AppTheme.instantGreen,
      ),
      _PerformanceMetric(
        'Average rating',
        '${analytics.averageRating.toStringAsFixed(1)} / 5',
        Icons.star_outline,
        AppTheme.starColor,
      ),
      _PerformanceMetric(
        'Completion rate',
        _percent(analytics.averageCompletionRate),
        Icons.donut_large_outlined,
        const Color(0xFF7B61FF),
      ),
      _PerformanceMetric(
        'Customer satisfaction',
        _percent(analytics.customerSatisfaction),
        Icons.sentiment_satisfied_alt_outlined,
        AppTheme.accent,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1180
            ? 5
            : constraints.maxWidth >= 720
                ? 3
                : constraints.maxWidth >= 480
                    ? 2
                    : 1;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: FixNowHoverCard(
                  padding: const EdgeInsets.all(17),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: metric.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(metric.icon, color: metric.color),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              metric.label,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                metric.value,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PerformanceMetric {
  const _PerformanceMetric(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _PerformancePanel extends StatelessWidget {
  const _PerformancePanel({
    required this.title,
    required this.child,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FixNowHoverCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _PerformerList extends StatelessWidget {
  const _PerformerList({
    required this.records,
    required this.icon,
    required this.color,
  });
  final List<TechnicianPerformanceRecord> records;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const _PerformanceEmpty('No technician performance yet');
    }
    return Column(
      children: [
        for (var index = 0; index < records.length; index++) ...[
          Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.12),
                foregroundColor: color,
                child: Icon(icon, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      records[index].technician.name,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      '${records[index].completedJobs} jobs · '
                      '${records[index].averageRating.toStringAsFixed(1)} rating',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _ScoreBadge(score: records[index].score),
            ],
          ),
          if (index != records.length - 1) const Divider(height: 24),
        ],
      ],
    );
  }
}

class _LeaderboardTable extends StatelessWidget {
  const _LeaderboardTable({required this.records});
  final List<TechnicianPerformanceRecord> records;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Rank')),
          DataColumn(label: Text('Technician')),
          DataColumn(label: Text('Revenue'), numeric: true),
          DataColumn(label: Text('Completed'), numeric: true),
          DataColumn(label: Text('Rating'), numeric: true),
          DataColumn(label: Text('Completion'), numeric: true),
          DataColumn(label: Text('Satisfaction'), numeric: true),
          DataColumn(label: Text('Score'), numeric: true),
        ],
        rows: [
          for (var index = 0; index < records.length; index++)
            DataRow(
              cells: [
                DataCell(Text('#${index + 1}')),
                DataCell(Text(records[index].technician.name)),
                DataCell(Text(_money(records[index].revenue))),
                DataCell(Text('${records[index].completedJobs}')),
                DataCell(Text(
                  '${records[index].averageRating.toStringAsFixed(1)} '
                  '(${records[index].reviewCount})',
                )),
                DataCell(Text(_percent(records[index].completionRate))),
                DataCell(Text(
                  _percent(records[index].customerSatisfaction),
                )),
                DataCell(_ScoreBadge(score: records[index].score)),
              ],
            ),
        ],
      ),
    );
  }
}

class _BranchRankingList extends StatelessWidget {
  const _BranchRankingList({required this.records});
  final List<BranchPerformanceRecord> records;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < records.length; index++) ...[
          Row(
            children: [
              CircleAvatar(
                backgroundColor: index == 0
                    ? AppTheme.starColor.withValues(alpha: 0.18)
                    : AppTheme.surface,
                foregroundColor:
                    index == 0 ? const Color(0xFF9A6700) : AppTheme.primary,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      records[index].branch.name,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${records[index].completedJobs} completed · '
                      '${records[index].averageRating.toStringAsFixed(1)} rating · '
                      '${_percent(records[index].completionRate)} completion',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _money(records[index].revenue),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    '${records[index].score.toStringAsFixed(0)} score',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (index != records.length - 1) const Divider(height: 24),
        ],
      ],
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});
  final double score;

  @override
  Widget build(BuildContext context) {
    final color = score >= 75
        ? AppTheme.instantGreen
        : score >= 50
            ? AppTheme.accent
            : const Color(0xFFD95C2A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        score.toStringAsFixed(0),
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _PerformanceEmpty extends StatelessWidget {
  const _PerformanceEmpty(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      ),
    );
  }
}

String _money(double amount) => NumberFormat.currency(
      locale: 'en_IN',
      symbol: '\u20B9',
      decimalDigits: 0,
    ).format(amount);

String _percent(double value) => '${value.toStringAsFixed(0)}%';
