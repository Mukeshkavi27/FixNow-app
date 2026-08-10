import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../bookings/domain/booking.dart';
import '../domain/bill.dart';

class BillPdfService {
  const BillPdfService();

  Future<void> openBillPdf({
    required Bill bill,
    required Booking booking,
  }) async {
    final bytes = await _buildPdf(bill: bill, booking: booking);
    await _share(bytes, bill.bookingId);
  }

  Future<void> openBillPdfFromBill(Bill bill) async {
    final bytes = await _buildPdf(bill: bill);
    await _share(bytes, bill.bookingId);
  }

  Future<void> _share(Uint8List bytes, String bookingId) async {
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'fixnow-bill-$bookingId.pdf',
    );
  }

  Future<Uint8List> _buildPdf({
    required Bill bill,
    Booking? booking,
  }) async {
    final document = pw.Document();
    final createdAt = DateFormat('dd MMM yyyy, hh:mm a').format(bill.createdAt);
    final customerName =
        booking?.customerName ?? bill.customerName ?? 'Customer';
    final phone = booking?.phone ?? '-';
    final address = booking?.address ?? bill.serviceAddress ?? '-';
    final applianceType =
        booking?.applianceType ?? bill.applianceType ?? 'Service';
    final problemDescription = booking?.problemDescription ?? '-';
    final preferredTime = booking?.preferredTime ?? bill.preferredTime ?? '-';
    final technicianName =
        booking?.technicianName ?? bill.technicianName ?? 'Technician';
    final technicianCompleted =
        booking?.technicianCompletedWorkAt ?? bill.technicianCompletedWorkAt;
    final customerConfirmed = booking?.customerConfirmedWorkCompletedAt ??
        bill.customerConfirmedWorkCompletedAt;

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'FixNow',
                        style: pw.TextStyle(
                          fontSize: 28,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue700,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text('Home appliance service invoice'),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'FINAL BILL',
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text('Bill ID: ${bill.id}'),
                      pw.Text('Date: $createdAt'),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 28),
              _sectionTitle('Customer'),
              _row('Name', customerName),
              _row('Phone', phone),
              _row('Address', address),
              pw.SizedBox(height: 18),
              _sectionTitle('Service'),
              _row('Appliance', applianceType),
              _row('Problem', problemDescription),
              _row('Preferred time', preferredTime),
              _row('Technician', technicianName),
              _row(
                'Technician completion',
                technicianCompleted == null
                    ? 'Recorded'
                    : DateFormat('dd MMM yyyy, hh:mm a')
                        .format(technicianCompleted),
              ),
              _row(
                'Customer confirmation',
                customerConfirmed == null
                    ? 'Recorded'
                    : DateFormat('dd MMM yyyy, hh:mm a')
                        .format(customerConfirmed),
              ),
              pw.SizedBox(height: 22),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: const {
                  0: pw.FlexColumnWidth(3),
                  1: pw.FlexColumnWidth(1),
                },
                children: [
                  pw.TableRow(
                    decoration:
                        const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _cell('Description', bold: true),
                      _cell('Amount', bold: true, alignRight: true),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      _cell('$applianceType service charges'),
                      _cell(
                        'INR ${bill.amount.toStringAsFixed(0)}',
                        alignRight: true,
                      ),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      _cell('Total', bold: true),
                      _cell(
                        'INR ${bill.amount.toStringAsFixed(0)}',
                        bold: true,
                        alignRight: true,
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 18),
              _row('Payment status', bill.paymentStatusLabel),
              _row('Payment mode', bill.paymentModeLabel),
              pw.Spacer(),
              pw.Divider(color: PdfColors.grey300),
              pw.Text(
                'This invoice is generated after technician completion request and customer work-completion confirmation.',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ],
          );
        },
      ),
    );
    return document.save();
  }

  pw.Widget _sectionTitle(String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Text(
        value,
        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget _row(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 140,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Expanded(child: pw.Text(value)),
        ],
      ),
    );
  }

  pw.Widget _cell(
    String value, {
    bool bold = false,
    bool alignRight = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(10),
      child: pw.Text(
        value,
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }
}
