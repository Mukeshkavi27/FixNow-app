import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_theme.dart';
import '../../auth/domain/app_user.dart';
import '../../bookings/domain/booking.dart';
import '../../shared/domain/bill.dart';
import '../domain/overtime_record.dart';

class OvertimeSummaryPanel extends StatelessWidget {
  const OvertimeSummaryPanel({
    super.key,
    required this.records,
    required this.bookings,
    required this.bills,
    this.technicians = const [],
    this.title = 'Overtime monitoring',
  });

  final List<OvertimeRecord> records;
  final List<Booking> bookings;
  final List<Bill> bills;
  final List<AppUser> technicians;
  final String title;

  @override
  Widget build(BuildContext context) {
    final visible = records.take(5).toList();
    final names = {
      for (final technician in technicians) technician.uid: technician.name
    };
    final summaries = [
      for (final record in records)
        summarizeOvertime(record: record, bookings: bookings, bills: bills),
    ];
    final totalBookings = summaries.fold<int>(
      0,
      (total, summary) => total + summary.extraBookings,
    );
    final totalRevenue = summaries.fold<double>(
      0,
      (total, summary) => total + summary.extraRevenue,
    );
    final hasActiveOvertime = records.any((record) => record.isActive);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF3B46B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.nights_stay_outlined, color: Color(0xFFC45A13)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFC45A13),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  hasActiveOvertime ? 'WORKING OVERTIME' : 'OVERTIME RECORDED',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Automatically detected from verified GPS activity after 10:00 PM.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _OvertimeMetric(label: 'Sessions', value: '${records.length}'),
              _OvertimeMetric(label: 'Extra bookings', value: '$totalBookings'),
              _OvertimeMetric(
                label: 'Extra revenue',
                value: NumberFormat.currency(
                  locale: 'en_IN',
                  symbol: '₹',
                  decimalDigits: 0,
                ).format(totalRevenue),
              ),
            ],
          ),
          if (visible.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (var index = 0; index < visible.length; index++) ...[
              _OvertimeRow(
                record: visible[index],
                summary: summarizeOvertime(
                  record: visible[index],
                  bookings: bookings,
                  bills: bills,
                ),
                technicianName: names[visible[index].technicianId],
              ),
              if (index != visible.length - 1) const Divider(height: 18),
            ],
          ],
        ],
      ),
    );
  }
}

class _OvertimeRow extends StatelessWidget {
  const _OvertimeRow({
    required this.record,
    required this.summary,
    this.technicianName,
  });

  final OvertimeRecord record;
  final OvertimeSummary summary;
  final String? technicianName;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CircleAvatar(
          backgroundColor: Color(0xFFFFE4C2),
          child: Icon(Icons.engineering_outlined, color: Color(0xFFC45A13)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                technicianName?.trim().isNotEmpty == true
                    ? technicianName!
                    : 'Technician ${record.technicianId}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                '${DateFormat('dd MMM yyyy').format(record.startedAt)} · '
                '${formatOvertimeDuration(summary.duration)} · '
                '${summary.extraBookings} extra booking${summary.extraBookings == 1 ? '' : 's'} · '
                '${NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(summary.extraRevenue)}',
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OvertimeMetric extends StatelessWidget {
  const _OvertimeMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF2D2AE)),
      ),
      child: Text.rich(
        TextSpan(
          text: '$label: ',
          style: const TextStyle(color: AppTheme.textSecondary),
          children: [
            TextSpan(
              text: value,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
