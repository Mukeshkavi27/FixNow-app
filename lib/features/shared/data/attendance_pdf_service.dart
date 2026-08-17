import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../auth/domain/app_user.dart';
import '../../technician/domain/attendance.dart';

class AttendancePdfService {
  const AttendancePdfService();

  Future<void> shareAttendanceSheet({
    required AppUser technician,
    required List<Attendance> records,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final bytes = await _build(
      technician: technician,
      records: records,
      startDate: startDate,
      endDate: endDate,
    );
    final key =
        '${DateFormat('yyyyMMdd').format(startDate)}-to-${DateFormat('yyyyMMdd').format(endDate)}';
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'fixnow-attendance-${technician.uid}-$key.pdf',
    );
  }

  Future<Uint8List> _build({
    required AppUser technician,
    required List<Attendance> records,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final pdf = pw.Document();
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    final employmentStart = technician.approvedAt ?? technician.createdAt;
    final rows = <_AttendancePdfRow>[];
    final byDay = <String, Attendance>{
      for (final record in records)
        if (!record.timestamp.isBefore(start) && !record.timestamp.isAfter(end))
          DateFormat('yyyy-MM-dd').format(record.timestamp): record,
    };
    final today = DateTime.now();
    for (var day = start;
        !day.isAfter(end) && !day.isAfter(DateTime(today.year, today.month, today.day));
        day = day.add(const Duration(days: 1))) {
      if (day.isBefore(DateTime(employmentStart.year, employmentStart.month,
          employmentStart.day))) {
        continue;
      }
      final record = byDay[DateFormat('yyyy-MM-dd').format(day)];
      rows.add(_AttendancePdfRow(day: day, record: record));
    }
    final present = rows.where((row) => row.status == 'present').length;
    final late = rows.where((row) => row.status == 'late').length;
    final absent = rows.where((row) => row.status == 'absent').length;
    final notMarked = rows.where((row) => row.status == 'not_marked').length;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            color: PdfColor.fromInt(0xFF0F55D8),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('FixNow',
                    style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text('TECHNICIAN ATTENDANCE SHEET',
                    style: const pw.TextStyle(color: PdfColors.white)),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          pw.Text(technician.name.isEmpty ? technician.email : technician.name,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Text('${technician.email}  |  ${technician.phone}'),
          pw.Text(
            'Period: ${DateFormat('dd MMM yyyy').format(start)} – ${DateFormat('dd MMM yyyy').format(end)}',
          ),
          pw.SizedBox(height: 12),
          pw.Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _summary('Present', present, PdfColors.green),
              _summary('Late', late, PdfColors.orange),
              _summary('Absent', absent, PdfColors.red),
              _summary('Not marked', notMarked, PdfColors.grey),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
            headerStyle: pw.TextStyle(
                color: PdfColors.white, fontWeight: pw.FontWeight.bold),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 6),
            headers: const ['Date', 'Punch in', 'Status', 'Late by', 'Verification'],
            data: rows
                .map((row) => [
                      DateFormat('dd MMM, EEE').format(row.day),
                      row.record == null
                          ? '-'
                          : DateFormat('hh:mm a').format(row.record!.timestamp),
                      row.statusLabel,
                      row.lateDurationLabel,
                      row.record == null
                          ? 'Not received'
                          : row.record!.faceMatchPassed
                              ? 'Selfie verified'
                              : 'Needs review',
                    ])
                .toList(),
          ),
          pw.SizedBox(height: 14),
          pw.Text(
            'Late time is calculated against the FixNow 9:45 AM attendance cutoff. '
            'Attendance records are retained from the technician start date.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return pdf.save();
  }

  pw.Widget _summary(String label, int value, PdfColor color) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: color),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Text('$label: $value',
            style: pw.TextStyle(color: color, fontWeight: pw.FontWeight.bold)),
      );
}

class _AttendancePdfRow {
  const _AttendancePdfRow({required this.day, required this.record});

  final DateTime day;
  final Attendance? record;

  String get status => record?.status ?? 'not_marked';
  String get statusLabel => switch (status) {
        'present' => 'Present',
        'late' => 'Late',
        'absent' => 'Absent',
        _ => 'Not marked',
      };

  String get lateDurationLabel {
    if (status != 'late' || record == null) return '-';
    final cutoff = DateTime(day.year, day.month, day.day, 9, 45);
    final delay = record!.timestamp.difference(cutoff);
    if (delay <= Duration.zero) return 'Late (admin)';
    final hours = delay.inHours;
    final minutes = delay.inMinutes.remainder(60);
    if (hours == 0) return '$minutes min';
    return minutes == 0 ? '$hours hr' : '$hours hr $minutes min';
  }
}
