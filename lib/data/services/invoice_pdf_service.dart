import '../../core/utils/quantity_display_helper.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

final PdfColor _primaryColor = PdfColor.fromInt(0xFF0D9488); // MediBro Teal
final PdfColor _darkGrey = PdfColor.fromInt(0xFF1E293B);
final PdfColor _lightBg = PdfColor.fromInt(0xFFF8FAFC);
final PdfColor _lightRow = PdfColor.fromInt(0xFFF1F5F9);
final PdfColor _border = PdfColor.fromInt(0xFFE2E8F0);

class InvoicePdfService {
  static Future<Map<String, String>> _loadPharmacyInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'name': prefs.getString('pharmacy_name') ?? 'MediBro Pharmacy',
      'address': prefs.getString('pharmacy_address') ?? 'Dhaka, Bangladesh',
      'phone': prefs.getString('pharmacy_phone') ?? '',
      'owner_name': prefs.getString('owner_name') ?? '',
    };
  }

  /// Generate document bytes for an invoice
  static Future<Uint8List> generateInvoicePdfBytes({
    required Map<String, dynamic> exportData,
  }) async {
    final pharma = await _loadPharmacyInfo();
    final pdf = pw.Document();

    final String exportId =
        exportData['export_id']?.toString() ??
        exportData['id']?.toString() ??
        '';
    final String invoiceNumber =
        exportData['invoice_number']?.toString() ??
        (exportId.length >= 8
            ? exportId.substring(0, 8).toUpperCase()
            : exportId);

    final String custName =
        exportData['cust_name'] ??
        exportData['customer_name'] ??
        'Walk-in Customer';
    final String custPhone =
        exportData['cust_phone']?.toString() ??
        exportData['customer_phone']?.toString() ??
        '';
    final String custAddress = exportData['cust_address']?.toString() ?? '';
    final String paymentStatus =
        (exportData['payment_status']?.toString() ?? 'PAID').toUpperCase();

    DateTime exportDate;
    try {
      final dateStr = exportData['exported_at'] ?? exportData['created_at'];
      exportDate =
          dateStr != null
              ? DateTime.parse(dateStr.toString()).toLocal()
              : DateTime.now();
    } catch (_) {
      exportDate = DateTime.now();
    }

    final double totalAmount =
        double.tryParse(
          exportData['total_amount']?.toString() ??
              exportData['total_price']?.toString() ??
              exportData['grand_total']?.toString() ??
              '0',
        ) ??
        0.0;
    final double paidAmount =
        double.tryParse(exportData['paid_amount']?.toString() ?? '0') ?? 0.0;
    final double dueAmount =
        double.tryParse(
          exportData['due_amount']?.toString() ??
              (totalAmount - paidAmount).toString(),
        ) ??
        (totalAmount - paidAmount);

    final double discountValue =
        double.tryParse(
          exportData['discount_amount']?.toString() ??
              exportData['discount_value']?.toString() ??
              '0',
        ) ??
        0.0;
    final String discountType =
        exportData['discount_type']?.toString() ?? 'fixed';

    final List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(
      exportData['items'] ?? exportData['invoice_items'] ?? [],
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ── HEADER ──────────────────────────────────────────────
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: pw.BoxDecoration(
                  color: _primaryColor,
                  borderRadius: pw.BorderRadius.circular(12),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          pharma['name']!,
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        if (pharma['address']!.isNotEmpty)
                          pw.Text(
                            pharma['address']!,
                            style: const pw.TextStyle(
                              color: PdfColors.white,
                              fontSize: 9,
                            ),
                          ),
                        if (pharma['phone']!.isNotEmpty)
                          pw.Text(
                            'Phone: ${pharma['phone']!}',
                            style: const pw.TextStyle(
                              color: PdfColors.white,
                              fontSize: 9,
                            ),
                          ),
                        if (pharma['owner_name']!.isNotEmpty)
                          pw.Text(
                            'Owner: ${pharma['owner_name']!}',
                            style: const pw.TextStyle(
                              color: PdfColors.white,
                              fontSize: 9,
                            ),
                          ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'INVOICE',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 22,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          '#$invoiceNumber',
                          style: const pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 18),

              // ── CUSTOMER + DATE ROW ──────────────────────────────────
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: _lightBg,
                        borderRadius: pw.BorderRadius.circular(10),
                        border: pw.Border.all(color: _border),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Bill To',
                            style: pw.TextStyle(
                              color: _primaryColor,
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 9,
                            ),
                          ),
                          pw.SizedBox(height: 5),
                          pw.Text(
                            custName,
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: _darkGrey,
                            ),
                          ),
                          if (custPhone.isNotEmpty)
                            _metaRow('Phone', custPhone),
                          if (custAddress.isNotEmpty)
                            _metaRow('Address', custAddress),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 14),
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: _lightBg,
                        borderRadius: pw.BorderRadius.circular(10),
                        border: pw.Border.all(color: _border),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Invoice Details',
                            style: pw.TextStyle(
                              color: _primaryColor,
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 9,
                            ),
                          ),
                          pw.SizedBox(height: 5),
                          _metaRow(
                            'Date',
                            DateFormat('dd MMM yyyy').format(exportDate),
                          ),
                          _metaRow(
                            'Time',
                            DateFormat('hh:mm a').format(exportDate),
                          ),
                          _metaRow('Payment Status', paymentStatus),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 18),

              // ── ITEMS TABLE ──────────────────────────────────────────
              pw.Text(
                'Purchased Items',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: _darkGrey,
                ),
              ),
              pw.SizedBox(height: 6),

              pw.Table(
                border: pw.TableBorder.all(color: _border, width: 0.8),
                columnWidths: const {
                  0: pw.FlexColumnWidth(0.8), // SL
                  1: pw.FlexColumnWidth(4.2), // Medicine
                  2: pw.FlexColumnWidth(1.5), // Qty
                  3: pw.FlexColumnWidth(1.8), // Unit Price
                  4: pw.FlexColumnWidth(2.0), // Total
                },
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: _primaryColor),
                    children: [
                      _tableHeader('#', align: pw.TextAlign.center),
                      _tableHeader('Medicine Description'),
                      _tableHeader('Qty', align: pw.TextAlign.center),
                      _tableHeader(
                        'Unit Price (Tk)',
                        align: pw.TextAlign.right,
                      ),
                      _tableHeader('Total (Tk)', align: pw.TextAlign.right),
                    ],
                  ),
                  ...items.asMap().entries.map((entry) {
                    final i = entry.key;
                    final item = entry.value;
                    final rowBg = i.isEven ? PdfColors.white : _lightRow;

                    final medName =
                        item['med_name'] ??
                        item['medicine_name'] ??
                        item['name'] ??
                        '-';
                    final medType =
                        item['med_type']?.toString() ??
                        item['unit_type']?.toString() ??
                        '';
                    final strength = item['strength']?.toString() ?? '';
                    final batchNo = item['batch_number']?.toString() ?? '';

                    final parts = <String>[
                      if (medType.isNotEmpty) medType,
                      if (strength.isNotEmpty) strength,
                      if (batchNo.isNotEmpty) 'Batch: $batchNo',
                    ];
                    final subLine = parts.join(' | ');

                    final rawQtyStr = item['quantity']?.toString() ?? '1';
                    final itemTotal =
                        double.tryParse(
                          item['total_price']?.toString() ?? '0',
                        ) ??
                        0.0;
                    double unitPrice =
                        double.tryParse(
                          item['unit_price']?.toString() ??
                              item['export_rate']?.toString() ??
                              '0',
                        ) ??
                        0.0;

                    String qty;
                    if (rawQtyStr.endsWith('B') ||
                        rawQtyStr.endsWith('S') ||
                        rawQtyStr.endsWith('X')) {
                      qty = rawQtyStr;
                    } else {
                      final int rawQtyInt = int.tryParse(rawQtyStr) ?? 1;
                      final fmt = QuantityDisplayHelper.format(
                        totalUnits: rawQtyInt,
                        totalPrice:
                            itemTotal > 0 ? itemTotal : (unitPrice * rawQtyInt),
                        unitType: item['unit_type']?.toString(),
                        rawQuantity: (item['raw_quantity'] as num?)?.toInt(),
                        piecesPerStrip:
                            (item['pieces_per_strip'] as num?)?.toInt(),
                        stripsPerBox: (item['strips_per_box'] as num?)?.toInt(),
                        dosageForm:
                            item['dosage_form']?.toString() ??
                            item['med_type']?.toString(),
                      );
                      qty = fmt.quantityDisplay;
                      unitPrice = fmt.unitRate;
                    }

                    return pw.TableRow(
                      decoration: pw.BoxDecoration(color: rowBg),
                      children: [
                        _tableCell('${i + 1}', align: pw.TextAlign.center),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                medName.toString(),
                                style: pw.TextStyle(
                                  fontSize: 10,
                                  color: _darkGrey,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              if (subLine.isNotEmpty)
                                pw.Text(
                                  subLine,
                                  style: const pw.TextStyle(
                                    fontSize: 8,
                                    color: PdfColors.grey600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        _tableCell(qty, align: pw.TextAlign.center),
                        _tableCell(
                          unitPrice.toStringAsFixed(2),
                          align: pw.TextAlign.right,
                        ),
                        _tableCell(
                          itemTotal.toStringAsFixed(2),
                          align: pw.TextAlign.right,
                        ),
                      ],
                    );
                  }),
                ],
              ),

              pw.SizedBox(height: 16),

              // ── TOTALS ───────────────────────────────────────────────
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Container(
                  width: 220,
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: _lightBg,
                    borderRadius: pw.BorderRadius.circular(10),
                    border: pw.Border.all(color: _border),
                  ),
                  child: pw.Column(
                    children: [
                      _totalRow(
                        'Subtotal',
                        'Tk ${(totalAmount + (discountType == '%' ? (totalAmount * discountValue / 100) : discountValue)).toStringAsFixed(2)}',
                      ),
                      if (discountValue > 0)
                        _totalRow(
                          'Discount (${discountType == '%' ? '$discountValue%' : 'Flat'})',
                          '-Tk ${discountValue.toStringAsFixed(2)}',
                          valueColor: PdfColors.red700,
                        ),
                      pw.Divider(color: _border, height: 10),
                      _totalRow(
                        'Grand Total',
                        'Tk ${totalAmount.toStringAsFixed(2)}',
                        bold: true,
                        labelColor: _darkGrey,
                        valueColor: _primaryColor,
                      ),
                      _totalRow(
                        'Paid Amount',
                        'Tk ${paidAmount.toStringAsFixed(2)}',
                        valueColor: PdfColors.green700,
                      ),
                      _totalRow(
                        'Due Balance',
                        'Tk ${dueAmount > 0.001 ? dueAmount.toStringAsFixed(2) : '0.00'}',
                        bold: dueAmount > 0.001,
                        valueColor:
                            dueAmount > 0.001
                                ? PdfColors.red700
                                : PdfColors.green700,
                      ),
                    ],
                  ),
                ),
              ),

              pw.Spacer(),

              // ── FOOTER ───────────────────────────────────────────────
              pw.Divider(color: _border),
              pw.SizedBox(height: 6),
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'Thank you for your business! Please visit again.',
                      style: pw.TextStyle(
                        color: _primaryColor,
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'Generated by MediBro SaaS  |  ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}',
                      style: const pw.TextStyle(
                        color: PdfColors.grey600,
                        fontSize: 8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Print directly via printer dialog
  static Future<void> printInvoice({
    required BuildContext context,
    required Map<String, dynamic> exportData,
  }) async {
    try {
      final bytes = await generateInvoicePdfBytes(exportData: exportData);
      final exportId =
          exportData['export_id']?.toString() ??
          exportData['id']?.toString() ??
          'Invoice';
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => bytes,
        name: 'Invoice_$exportId.pdf',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Share or download PDF
  static Future<void> generateAndShare({
    required BuildContext context,
    required Map<String, dynamic> exportData,
  }) async {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
              SizedBox(width: 12),
              Text('Generating invoice PDF...'),
            ],
          ),
          duration: Duration(seconds: 4),
          backgroundColor: Color(0xFF0D9488),
        ),
      );
    }

    try {
      final bytes = await generateInvoicePdfBytes(exportData: exportData);
      final exportId =
          exportData['export_id']?.toString() ??
          exportData['id']?.toString() ??
          'Invoice';

      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      await Printing.sharePdf(bytes: bytes, filename: 'Invoice_$exportId.pdf');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invoice error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static pw.Widget _metaRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        children: [
          pw.Text(
            '$label: ',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: _darkGrey,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _tableHeader(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
          fontSize: 9,
        ),
      ),
    );
  }

  static pw.Widget _tableCell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(fontSize: 9, color: _darkGrey),
      ),
    );
  }

  static pw.Widget _totalRow(
    String label,
    String value, {
    bool bold = false,
    PdfColor? labelColor,
    PdfColor? valueColor,
  }) {
    final lColor = labelColor ?? PdfColors.grey700;
    final vColor = valueColor ?? _darkGrey;
    final style =
        bold
            ? pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)
            : const pw.TextStyle(fontSize: 9);

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style.copyWith(color: lColor)),
          pw.Text(value, style: style.copyWith(color: vColor)),
        ],
      ),
    );
  }
}
