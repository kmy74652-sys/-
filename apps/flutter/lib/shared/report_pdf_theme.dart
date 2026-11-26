import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'app_customizer.dart';
import 'organization_branding.dart';

String reportPdfSafeText(String value) => value
    .replaceAll('·', ' - ')
    .replaceAll('\uFFFD', '')
    .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), ' ');

class ReportPdfTheme {
  ReportPdfTheme(this.settings, {this.logo});

  final AppCustomizer settings;
  final pw.ImageProvider? logo;

  static Future<ReportPdfTheme> load() async {
    final settings = AppCustomizer.instance;
    await settings.load();
    final organizationBranding = await OrganizationBrandingStore.instance.forSession();
    if (settings.reportCompanyName.trim().isEmpty || settings.reportCompanyName == 'مؤسسة الشاعري للتجارة العامة') {
      settings.reportCompanyName = organizationBranding.name;
    }
    pw.ImageProvider? logo;
    final url = settings.reportLogoUrl.trim().isNotEmpty
        ? settings.reportLogoUrl.trim()
        : organizationBranding.logoUrl;
    if (url != null && url.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          logo = pw.MemoryImage(response.bodyBytes);
        }
      } catch (_) {}
    }
    return ReportPdfTheme(settings, logo: logo);
  }

  PdfColor get primary => PdfColor.fromInt(settings.reportPrimaryColor);
  PdfColor get heading => PdfColor.fromInt(settings.reportHeadingColor);
  double get fontSize => settings.reportFontSize;

  pw.Widget header(String title, {String? employee, String? branch, String? status, String? number}) {
    final defaultOrder = const ['company', 'branchName', 'phone', 'email', 'address', 'headerText', 'title', 'employee', 'taskBranch', 'status', 'number', 'exportDate'];
    final order = <String>[...settings.reportHeaderOrder, ...defaultOrder.where((key) => !settings.reportHeaderOrder.contains(key))];
    final content = <pw.Widget>[];
    pw.Widget line(String key, String value, {double size = 10, bool bold = false, PdfColor? color}) {
      final layout = settings.reportHeaderLayout(key);
      final align = layout['align'] == 'left' ? pw.TextAlign.left : layout['align'] == 'center' ? pw.TextAlign.center : pw.TextAlign.right;
      final configuredSize = settings.reportHeaderLayouts.containsKey(key) ? (layout['size'] as num).toDouble() : size;
      final x = (layout['x'] as num).toDouble();
      final y = (layout['y'] as num).toDouble();
      return pw.Container(
        margin: pw.EdgeInsets.only(left: x > 0 ? x : 0, right: x < 0 ? -x : 0, top: y > 0 ? y : 0, bottom: y < 0 ? -y : 0),
        child: pw.Text(reportPdfSafeText(value), textDirection: pw.TextDirection.rtl, textAlign: align, style: pw.TextStyle(fontSize: configuredSize, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color)),
      );
    }
    for (final key in order) {
      switch (key) {
        case 'company': if (settings.reportCompanyName.trim().isNotEmpty) content.add(line(key, settings.reportCompanyName, size: 15, bold: true, color: primary));
        case 'branchName': if (settings.reportBranchName.trim().isNotEmpty) content.add(line(key, settings.reportBranchName));
        case 'phone': if (settings.reportPhone.trim().isNotEmpty) content.add(line(key, 'الهاتف: ${settings.reportPhone}', size: 8));
        case 'email': if (settings.reportEmail.trim().isNotEmpty) content.add(line(key, 'البريد الإلكتروني: ${settings.reportEmail}', size: 8));
        case 'address': if (settings.reportAddress.trim().isNotEmpty) content.add(line(key, 'العنوان: ${settings.reportAddress}', size: 8));
        case 'headerText': if (settings.reportHeaderText.trim().isNotEmpty) content.add(line(key, settings.reportHeaderText));
        case 'title': content.add(pw.SizedBox(height: 5)); content.add(line(key, title, size: 19, bold: true, color: heading));
        case 'employee': if (settings.reportShowEmployee && employee != null && employee.trim().isNotEmpty) content.add(line(key, 'الموظف: $employee', size: 8));
        case 'taskBranch': if (settings.reportShowBranch && branch != null && branch.trim().isNotEmpty) content.add(line(key, 'الفرع: $branch', size: 8));
        case 'status': if (settings.reportShowStatus && status != null && status.trim().isNotEmpty) content.add(line(key, 'الحالة: $status', size: 8));
        case 'number': if (settings.reportShowNumber && number != null && number.trim().isNotEmpty) content.add(line(key, 'رقم التقرير: $number', size: 8));
        case 'exportDate': if (settings.reportShowExportDate) content.add(line(key, 'تاريخ التصدير: ${DateTime.now().toLocal().toString().split('.').first}', size: 8));
      }
    }
    final row = pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      if (settings.reportLogoPosition == 'right' && logo != null) pw.Container(width: settings.reportLogoSize, height: settings.reportLogoSize, child: pw.Image(logo!, fit: pw.BoxFit.contain)),
      pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: content)),
      if (settings.reportLogoPosition == 'left' && logo != null) pw.Container(width: settings.reportLogoSize, height: settings.reportLogoSize, child: pw.Image(logo!, fit: pw.BoxFit.contain)),
    ]);
    final wrapped = settings.reportLogoPosition == 'center' && logo != null ? pw.Column(children: [pw.Image(logo!, width: settings.reportLogoSize, height: settings.reportLogoSize, fit: pw.BoxFit.contain), pw.SizedBox(height: 4), row]) : row;
    return pw.Container(padding: const pw.EdgeInsets.only(bottom: 10), decoration: settings.reportHeaderStyle == 'minimal' ? null : pw.BoxDecoration(color: settings.reportHeaderStyle == 'band' ? PdfColor.fromHex('#EAF4F0') : PdfColors.white, border: settings.reportHeaderStyle == 'boxed' ? pw.Border.all(color: primary) : null), child: pw.Padding(padding: const pw.EdgeInsets.all(8), child: wrapped));
  }

  pw.TableBorder get tableBorder => settings.reportTableStyle == 'simple' ? pw.TableBorder.symmetric(inside: pw.BorderSide(color: PdfColors.grey300, width: .5)) : pw.TableBorder.all(color: primary, width: .7);
  pw.BoxDecoration get tableHeaderDecoration => pw.BoxDecoration(color: settings.reportTableStyle == 'colored' ? PdfColor.fromHex('#DCEFE8') : PdfColor.fromHex('#EAF4F0'));

  pw.Widget footer() => settings.reportShowFooter && settings.reportFooterText.trim().isNotEmpty ? pw.Padding(padding: const pw.EdgeInsets.only(top: 12), child: pw.Text(reportPdfSafeText(settings.reportFooterText), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl, style: pw.TextStyle(fontSize: 8, color: heading))) : pw.SizedBox();

  static Future<pw.Font> regularFont() async => pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
  static Future<pw.Font> boldFont() async => pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'));
}
