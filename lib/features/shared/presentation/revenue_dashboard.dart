import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/fixnow_admin_shell.dart';
import '../../../core/branches/branch_info.dart';
import '../../auth/domain/app_user.dart';
import '../../bookings/domain/booking.dart';
import '../domain/bill.dart';
import '../domain/revenue_analytics.dart';

class RevenueDashboard extends StatefulWidget {
  const RevenueDashboard({
    super.key,
    required this.bills,
    required this.bookings,
    required this.branches,
    required this.technicians,
    required this.now,
    this.lockedBranchId,
    this.title = 'Revenue and analytics',
    this.subtitle = 'Paid collection performance and reports',
  });

  final List<Bill> bills;
  final List<Booking> bookings;
  final List<BranchInfo> branches;
  final List<AppUser> technicians;
  final DateTime now;
  final String? lockedBranchId;
  final String title;
  final String subtitle;

  @override
  State<RevenueDashboard> createState() => _RevenueDashboardState();
}

class _RevenueDashboardState extends State<RevenueDashboard> {
  String _branchFilter = 'all';

  @override
  void initState() {
    super.initState();
    _branchFilter = widget.lockedBranchId ?? 'all';
  }

  @override
  void didUpdateWidget(covariant RevenueDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lockedBranchId != oldWidget.lockedBranchId) {
      _branchFilter = widget.lockedBranchId ?? 'all';
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedBranch = _branchFilter == 'all' ? null : _branchFilter;
    final analytics = RevenueAnalytics.calculate(
      bills: widget.bills,
      bookings: widget.bookings,
      branches: widget.branches,
      technicians: widget.technicians,
      now: widget.now,
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
                width: 230,
                child: DropdownButtonFormField<String>(
                  initialValue: _branchFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Revenue branch',
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
        _MetricGrid(analytics: analytics),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final weekly = _RevenuePanel(
              title: 'Daily revenue',
              subtitle: 'Paid revenue over the last 7 days',
              child: _RevenueBarChart(points: analytics.dailyTrend),
            );
            final monthly = _RevenuePanel(
              title: 'Monthly revenue',
              subtitle: 'Paid revenue over the last 12 months',
              child: _RevenueBarChart(
                points: analytics.monthlyTrend,
                color: AppTheme.accent,
              ),
            );
            return wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: weekly),
                      const SizedBox(width: 18),
                      Expanded(child: monthly),
                    ],
                  )
                : Column(
                    children: [weekly, const SizedBox(height: 18), monthly],
                  );
          },
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final panels = [
              _RevenuePanel(
                title: 'Branch-wise revenue',
                subtitle: 'Paid collections by branch',
                child: _BreakdownList(
                  items: analytics.branchRevenue,
                  emptyMessage: 'No branch revenue yet',
                ),
              ),
              _RevenuePanel(
                title: 'Technician revenue',
                subtitle: 'Paid collections by technician',
                child: _BreakdownList(
                  items: analytics.technicianRevenue,
                  emptyMessage: 'No technician revenue yet',
                  color: AppTheme.instantGreen,
                ),
              ),
              _RevenuePanel(
                title: 'Service revenue',
                subtitle: 'Paid collections by appliance service',
                child: _BreakdownList(
                  items: analytics.serviceRevenue,
                  emptyMessage: 'No service revenue yet',
                  color: AppTheme.accent,
                ),
              ),
            ];
            if (constraints.maxWidth >= 1080) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < panels.length; i++) ...[
                    Expanded(child: panels[i]),
                    if (i != panels.length - 1) const SizedBox(width: 18),
                  ],
                ],
              );
            }
            return Column(
              children: [
                for (var i = 0; i < panels.length; i++) ...[
                  panels[i],
                  if (i != panels.length - 1) const SizedBox(height: 18),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        _RevenuePanel(
          title: 'Revenue reports',
          subtitle: 'Period totals calculated from confirmed paid bills',
          child: _RevenueReportTable(rows: analytics.reportRows),
        ),
        const SizedBox(height: 18),
        _RevenuePanel(
          title: 'Recent paid bills',
          subtitle: '${analytics.paidBillCount} confirmed collection(s)',
          child: analytics.recentPaidBills.isEmpty
              ? const _RevenueEmpty('No paid bills yet')
              : Column(
                  children: [
                    for (var i = 0;
                        i < analytics.recentPaidBills.length;
                        i++) ...[
                      _PaidBillRow(
                        bill: analytics.recentPaidBills[i],
                        booking: _bookingFor(
                          analytics.recentPaidBills[i].bookingId,
                        ),
                      ),
                      if (i != analytics.recentPaidBills.length - 1)
                        const Divider(height: 1),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Booking? _bookingFor(String bookingId) {
    for (final booking in widget.bookings) {
      if (booking.id == bookingId) return booking;
    }
    return null;
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.analytics});
  final RevenueAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      (
        'Daily revenue',
        analytics.today,
        Icons.today_outlined,
        AppTheme.primary
      ),
      (
        'Weekly revenue',
        analytics.week,
        Icons.date_range_outlined,
        AppTheme.accent
      ),
      (
        'Monthly revenue',
        analytics.month,
        Icons.calendar_month_outlined,
        AppTheme.instantGreen
      ),
      (
        'Yearly revenue',
        analytics.year,
        Icons.insights_outlined,
        const Color(0xFF7B61FF)
      ),
      (
        'All-time revenue',
        analytics.allTime,
        Icons.account_balance_wallet_outlined,
        const Color(0xFF0F766E)
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
                child: _RevenueMetricCard(
                  label: metric.$1,
                  value: _money(metric.$2),
                  icon: metric.$3,
                  color: metric.$4,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RevenueMetricCard extends StatelessWidget {
  const _RevenueMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FixNowHoverCard(
      padding: const EdgeInsets.all(17),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
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
                    value,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
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
    );
  }
}

class _RevenuePanel extends StatelessWidget {
  const _RevenuePanel({
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
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
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
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _RevenueBarChart extends StatelessWidget {
  const _RevenueBarChart({
    required this.points,
    this.color = AppTheme.primary,
  });
  final List<RevenuePoint> points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final maxAmount = points.fold<double>(
      0,
      (maximum, point) => point.amount > maximum ? point.amount : maximum,
    );
    return SizedBox(
      height: 190,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final point in points)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      point.amount == 0 ? '' : _compactMoney(point.amount),
                      maxLines: 1,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Tooltip(
                      message: '${point.label}: ${_money(point.amount)}',
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        height: maxAmount == 0
                            ? 4
                            : 112 * (point.amount / maxAmount).clamp(0.04, 1),
                        decoration: BoxDecoration(
                          color: point.amount == 0
                              ? AppTheme.divider
                              : color.withValues(alpha: 0.82),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      point.label,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BreakdownList extends StatelessWidget {
  const _BreakdownList({
    required this.items,
    required this.emptyMessage,
    this.color = AppTheme.primary,
  });
  final List<RevenueBreakdown> items;
  final String emptyMessage;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return _RevenueEmpty(emptyMessage);
    return Column(
      children: [
        for (var i = 0; i < items.take(8).length; i++) ...[
          _BreakdownRow(item: items[i], color: color),
          if (i != items.take(8).length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.item, required this.color});
  final RevenueBreakdown item;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _money(item.amount),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: item.share.clamp(0, 1),
                  minHeight: 7,
                  backgroundColor: AppTheme.surface,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Text(
              '${item.billCount} bill(s)',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RevenueReportTable extends StatelessWidget {
  const _RevenueReportTable({required this.rows});
  final List<RevenueReportRow> rows;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Period')),
          DataColumn(label: Text('Paid bills'), numeric: true),
          DataColumn(label: Text('Revenue'), numeric: true),
          DataColumn(label: Text('Average bill'), numeric: true),
        ],
        rows: rows
            .map(
              (row) => DataRow(
                cells: [
                  DataCell(Text(row.period)),
                  DataCell(Text('${row.paidBills}')),
                  DataCell(Text(_money(row.revenue))),
                  DataCell(Text(_money(row.averageBill))),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

class _PaidBillRow extends StatelessWidget {
  const _PaidBillRow({required this.bill, required this.booking});
  final Bill bill;
  final Booking? booking;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFE8F1FF),
        foregroundColor: AppTheme.primary,
        child: Icon(Icons.receipt_long_outlined),
      ),
      title: Text(
        booking?.customerName ?? 'Booking ${bill.bookingId}',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${booking?.applianceType ?? 'Service'} · '
        '${DateFormat('dd MMM yyyy, hh:mm a').format(bill.revenueDate)}',
      ),
      trailing: Text(
        _money(bill.amount),
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _RevenueEmpty extends StatelessWidget {
  const _RevenueEmpty(this.message);
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

String _compactMoney(double amount) {
  if (amount >= 10000000) {
    return '\u20B9${(amount / 10000000).toStringAsFixed(1)}Cr';
  }
  if (amount >= 100000) return '\u20B9${(amount / 100000).toStringAsFixed(1)}L';
  if (amount >= 1000) return '\u20B9${(amount / 1000).toStringAsFixed(0)}K';
  return '\u20B9${amount.toStringAsFixed(0)}';
}
