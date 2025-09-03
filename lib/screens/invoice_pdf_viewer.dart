import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:typed_data';

class InvoicePDFViewer extends StatelessWidget {
  final Map<String, dynamic> invoiceData;
  final String invoiceId;

  const InvoicePDFViewer({
    super.key,
    required this.invoiceData,
    required this.invoiceId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice PDF'),
        backgroundColor: const Color(0xFF1E40AF),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _shareInvoice(),
            tooltip: 'Share Invoice',
          ),
        ],
      ),
      body: PdfPreview(
        build: (format) => _generatePdf(format),
        allowPrinting: true,
        allowSharing: true,
        canChangePageFormat: false,
        canDebug: false,
      ),
    );
  }

  /// Generates the PDF document.
  Future<Uint8List> _generatePdf(PdfPageFormat format) async {
    final pdf = pw.Document();

    // Load the universal Cairo font that supports both English and Arabic.
    // It's set as the default theme, so all widgets will use it unless overridden.
    final fontData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final cairoFont = pw.Font.ttf(fontData);

    // Get business info and customer info
    final businessInfo = invoiceData['businessInfo'] as Map<String, dynamic>? ?? {};
    final customerInfo = invoiceData['customerInfo'] as Map<String, dynamic>? ?? {};
    final items = invoiceData['items'] as List<dynamic>? ?? [];

    pdf.addPage(
      pw.MultiPage(
        // Set the default theme for the entire page to use the Cairo font
        theme: pw.ThemeData.withFont(
          base: cairoFont,
          bold: cairoFont, // Can use the same font and apply bold weight
        ),
        pageFormat: format,
        build: (pw.Context context) {
          return [
            _buildHeader(businessInfo),
            pw.SizedBox(height: 20),
            _buildInvoiceInfo(),
            pw.SizedBox(height: 20),
            _buildCustomerInfo(customerInfo),
            pw.SizedBox(height: 20),
            _buildItemsTable(items),
            pw.SizedBox(height: 20),
            _buildTotals(),
          ];
        },
        footer: (pw.Context context) {
          return _buildFooter(businessInfo);
        },
      ),
    );

    return pdf.save();
  }

  /// Checks if a string contains Arabic characters.
  bool _isArabic(String text) => RegExp(r'[\u0600-\u06FF]').hasMatch(text);

  /// Builds the header section of the invoice.
  pw.Widget _buildHeader(Map<String, dynamic> businessInfo) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                businessInfo['companyName'] ?? 'Elite Laundry',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue900,
                ),
              ),
              if (businessInfo['companyNameArabic'] != null)
                pw.Text(
                  businessInfo['companyNameArabic'],
                  style: const pw.TextStyle(fontSize: 18, color: PdfColors.grey600),
                  textDirection: pw.TextDirection.rtl,
                ),
              pw.SizedBox(height: 5),
              if (businessInfo['address'] != null)
                pw.Text(businessInfo['address'], style: const pw.TextStyle(fontSize: 10)),
              if (businessInfo['phone'] != null)
                pw.Text('Phone: ${businessInfo['phone']}', style: const pw.TextStyle(fontSize: 10)),
              if (businessInfo['email'] != null)
                pw.Text('Email: ${businessInfo['email']}', style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
        ),
        pw.SizedBox(width: 20),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'INVOICE',
              style: pw.TextStyle(
                fontSize: 28,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue900,
              ),
            ),
            if (businessInfo['taxId'] != null)
              pw.Text(
                businessInfo['taxId'],
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
              ),
          ],
        ),
      ],
    );
  }

  /// Builds the invoice details section (number, date, status, QR code).
  pw.Widget _buildInvoiceInfo() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Invoice #: ${invoiceData['invoiceNumber'] ?? 'N/A'}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Date: ${_formatTimestamp(invoiceData['timestamp'])}',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'Status: ${invoiceData['status']?.toString().toUpperCase() ?? 'PENDING'}',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: _getStatusColor(invoiceData['status']),
              ),
            ),
            if (invoiceData['qrCodeData'] != null)
              pw.Container(
                width: 60,
                height: 60,
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: invoiceData['qrCodeData'],
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Builds the customer information box.
  pw.Widget _buildCustomerInfo(Map<String, dynamic> customerInfo) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Customer Information',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
          ),
          pw.SizedBox(height: 5),
          pw.Text('Name: ${customerInfo['fullName'] ?? 'N/A'}'),
          pw.Text('Phone: ${customerInfo['mobile'] ?? customerInfo['phone'] ?? 'N/A'}'),
          if (customerInfo['email'] != null)
            pw.Text('Email: ${customerInfo['email']}'),
          if (customerInfo['clientCode'] != null)
            pw.Text('Client Code: ${customerInfo['clientCode']}'),
        ],
      ),
    );
  }

  /// Builds the table of line items, handling both English and Arabic text.
  pw.Widget _buildItemsTable(List<dynamic> items) {
    return pw.TableHelper.fromTextArray(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontSize: 12,
      ),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
      cellStyle: const pw.TextStyle(fontSize: 10),
      cellPadding: const pw.EdgeInsets.all(8),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.center,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
      },
      columnWidths: {
        0: const pw.FlexColumnWidth(3),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(1.5),
      },
      headers: ['Service', 'Qty', 'Price', 'Total'],
      data: items.map((item) {
        final itemName = item['name'] ?? 'Unknown Service';
        // Create a custom Text widget for the item name to handle text direction
        final itemNameWidget = pw.Text(
          itemName,
          textDirection: _isArabic(itemName) ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          textAlign: _isArabic(itemName) ? pw.TextAlign.right : pw.TextAlign.left,
        );
        return [
          itemNameWidget, // Use the custom widget
          '${item['quantity'] ?? 1}',
          '${(item['unitPrice'] ?? 0).toStringAsFixed(2)}',
          '${(item['total'] ?? 0).toStringAsFixed(2)}',
        ];
      }).toList(),
    );
  }

  /// Builds the totals section (Subtotal, VAT, Net Payable, etc.).
  pw.Widget _buildTotals() {
    final subtotal = invoiceData['subtotal'] ?? 0.0;
    final vatAmount = invoiceData['vatAmount'] ?? 0.0;
    final discount = invoiceData['discount'] ?? 0.0;
    final netPayable = invoiceData['netPayable'] ?? 0.0;
    final amountPaid = invoiceData['amountPaid'] ?? 0.0;
    final dueAmount = invoiceData['dueAmount'] ?? 0.0;

    return pw.Container(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 200,
        child: pw.Column(
          children: [
            _buildTotalRow('Subtotal:', '${subtotal.toStringAsFixed(2)}'),
            if (discount > 0)
              _buildTotalRow('Discount:', '-${discount.toStringAsFixed(2)}'),
            if (vatAmount > 0)
              _buildTotalRow('VAT:', '${vatAmount.toStringAsFixed(2)}'),
            pw.Divider(color: PdfColors.grey400),
            _buildTotalRow(
              'Net Payable:',
              '${netPayable.toStringAsFixed(2)}',
              isTotal: true,
            ),
            if (amountPaid > 0)
              _buildTotalRow('Amount Paid:', '${amountPaid.toStringAsFixed(2)}'),
            if (dueAmount > 0)
              _buildTotalRow(
                'Due Amount:',
                '${dueAmount.toStringAsFixed(2)}',
                isHighlight: true,
              ),
          ],
        ),
      ),
    );
  }

  /// Helper for a single row in the totals section.
  pw.Widget _buildTotalRow(String label, String amount, {bool isTotal = false, bool isHighlight = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontWeight: isTotal ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: isTotal ? 12 : 10,
              color: isHighlight ? PdfColors.red : PdfColors.black,
            ),
          ),
          pw.Text(
            amount,
            style: pw.TextStyle(
              fontWeight: isTotal ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: isTotal ? 12 : 10,
              color: isHighlight ? PdfColors.red : PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the footer of the invoice.
  pw.Widget _buildFooter(Map<String, dynamic> businessInfo) {
    return pw.Column(
      children: [
        pw.Divider(color: PdfColors.grey400),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (businessInfo['website'] != null)
                  pw.Text(
                    'Website: ${businessInfo['website']}',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                  ),
                if (businessInfo['cheerfulNotice'] != null)
                  pw.Text(
                    businessInfo['cheerfulNotice'],
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.blue700),
                    textDirection: _isArabic(businessInfo['cheerfulNotice']) ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                  ),
              ],
            ),
            pw.Text(
              'Generated: ${DateTime.now().toString().substring(0, 19)}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
            ),
          ],
        ),
      ],
    );
  }

  /// Formats a timestamp (from Firestore) into a readable string.
  String _formatTimestamp(dynamic timestamp) {
    try {
      DateTime date;
      if (timestamp is Timestamp) {
        date = timestamp.toDate();
      } else if (timestamp is String) {
        date = DateTime.parse(timestamp);
      } else if (timestamp is DateTime) {
        date = timestamp;
      } else {
        return 'Invalid date';
      }
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Invalid date';
    }
  }

  /// Returns a color based on the invoice status.
  PdfColor _getStatusColor(dynamic status) {
    final statusStr = status?.toString().toLowerCase() ?? '';
    switch (statusStr) {
      case 'pending':
        return PdfColors.orange;
      case 'paid':
      case 'delivered': // Add delivered status
        return PdfColors.green;
      case 'overdue':
        return PdfColors.red;
      default:
        return PdfColors.grey700;
    }
  }

  /// Shares the generated PDF.
  Future<void> _shareInvoice() async {
    final pdfData = await _generatePdf(PdfPageFormat.a4);
    await Printing.sharePdf(
      bytes: pdfData,
      filename: 'Invoice_${invoiceData['invoiceNumber'] ?? invoiceId}.pdf',
    );
  }
}