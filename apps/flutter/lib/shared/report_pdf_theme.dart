import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'app_customizer.dart';
import 'organization_branding.dart';

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
    final details = <String>[];
    if (settings.reportShowEmployee && employee != null && employee.trim().isNotEmpty) details.add('الموظف: $employee');
    if (settings.reportShowBranch && branch != null && branch.trim().isNotEmpty) details.add('الفرع: $branch');
    if (settings.reportShowStatus && status != null && status.trim().isNotEmpty) details.add('الحالة: $status');
    if (settings.reportShowNumber && number != null && number.trim().isNotEmpty) details.add('رقم التقرير: $number');
    if (settings.reportShowExportDate) details.add('تاريخ التصدير: ${DateTime.now().toLocal().toString().split('.').first}');
    final content = <pw.Widget>[
      pw.Text(settings.reportCompanyName, textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: primary)),
      if (settings.reportBranchName.trim().isNotEmpty) pw.Text(settings.reportBranchName, textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.right),
      if ([settings.reportPhone, settings.reportEmail, settings.reportAddress].any((v) => v.trim().isNotEmpty))
        pw.Text([settings.reportPhone, settings.reportEmail, settings.reportAddress].where((v) => v.trim().isNotEmpty).join(' · '), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8)),
      if (settings.reportHeaderText.trim().isNotEmpty) pw.Text(settings.reportHeaderText, textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.right),
      pw.SizedBox(height: 5),
      pw.Text(title, textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold, color: heading)),
      if (details.isNotEmpty) pw.Text(details.join('   |   '), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8)),
    ];
    final row = pw.Row(textDirection: pw.TextDirection.rtl, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      if (settings.reportLogoPosition == 'right' && logo != null) pw.Container(width: settings.reportLogoSize, height: settings.reportLogoSize, child: pw.Image(logo!, fit: pw.BoxFit.contain)),
      pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: content)),
      if (settings.reportLogoPosition == 'left' && logo != null) pw.Container(width: settings.reportLogoSize, height: settings.reportLogoSize, child: pw.Image(logo!, fit: pw.BoxFit.contain)),
    ]);
    final wrapped = settings.reportLogoPosition == 'center' && logo != null
        ? pw.Column(children: [pw.Image(logo!, width: settings.reportLogoSize, height: settings.reportLogoSize, fit: pw.BoxFit.contain), pw.SizedBox(height: 4), row])
        : row;
    return pw.Container(padding: const pw.EdgeInsets.only(bottom: 10), decoration: settings.reportHeaderStyle == 'minimal' ? null : pw.BoxDecoration(color: settings.reportHeaderStyle == 'band' ? PdfColor.fromHex('#EAF4F0') : PdfColors.white, border: settings.reportHeaderStyle == 'boxed' ? pw.Border.all(color: primary) : null), child: pw.Padding(padding: const pw.EdgeInsets.all(8), child: wrapped));
  }

  pw.TableBorder get tableBorder => settings.reportTableStyle == 'simple' ? pw.TableBorder.symmetric(inside: pw.BorderSide(color: PdfColors.grey300, width: .5)) : pw.TableBorder.all(color: primary, width: .7);
  pw.BoxDecoration get tableHeaderDecoration => pw.BoxDecoration(color: settings.reportTableStyle == 'colored' ? PdfColor.fromHex('#DCEFE8') : PdfColor.fromHex('#EAF4F0'));

  pw.Widget footer() => settings.reportShowFooter && settings.reportFooterText.trim().isNotEmpty ? pw.Padding(padding: const pw.EdgeInsets.only(top: 12), child: pw.Text(settings.reportFooterText, textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl, style: pw.TextStyle(fontSize: 8, color: heading))) : pw.SizedBox();

  static Future<pw.Font> regularFont() async => pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
  static Future<pw.Font> boldFont() async => pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'));
}
