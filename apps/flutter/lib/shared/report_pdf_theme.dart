import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'app_customizer.dart';
import 'organization_branding.dart';

/// Removes characters that cannot be rendered safely in a PDF text stream
/// without filtering valid Unicode punctuation. Arabic and general Unicode
/// punctuation such as (، ؛ ؟ … — « ») must remain intact.
String reportPdfSafeText(String value) => value
    .replaceAll('\uFFFD', '')
    .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]'), ' ')
    .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
    .trim();

Map<String, dynamic> _reportPdfSignatureMap(Object? raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is String) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  return <String, dynamic>{};
}

bool reportPdfIsSignature(Object? raw) {
  final value = _reportPdfSignatureMap(raw);
  return value['strokes'] is List ||
      value['signature_attachment_id'] != null ||
      value['signed_at'] != null ||
      value['acknowledged'] != null;
}

String? _reportPdfSignatureSvg(Object? raw) {
  final value = _reportPdfSignatureMap(raw);
  final paths = <String>[];
  final strokes = value['strokes'];
  if (strokes is List) {
    for (final stroke in strokes.whereType<String>()) {
      final commands = RegExp(r'([ML])\s*(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)')
          .allMatches(stroke)
          .map((match) => '${match.group(1)} ${match.group(2)} ${match.group(3)}')
          .join(' ');
      if (commands.isNotEmpty) paths.add(commands);
    }
  }
  if (paths.isEmpty) return null;
  return '<svg xmlns="http://www.w3.org/2000/svg" width="600" height="170" viewBox="0 0 600 170">'
      '<g fill="none" stroke="#111111" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">'
      '${paths.map((path) => '<path d="$path"/>').join()}'
      '</g></svg>';
}

pw.Widget reportPdfSignatureWidget(Object? raw) {
  final value = _reportPdfSignatureMap(raw);
  final svg = _reportPdfSignatureSvg(raw);
  final signed = value['acknowledged'] == true ? 'تم التوقيع والموافقة' : 'تم التوقيع';
  final signedAt = '${value['signed_at'] ?? ''}'.trim();
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      if (svg != null) pw.SvgImage(svg: svg, width: 170, height: 55, fit: pw.BoxFit.contain),
      pw.Text(svg == null && !reportPdfIsSignature(raw) ? 'لم يتم التوقيع' : signed, textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8)),
      if (signedAt.isNotEmpty) pw.Text(reportPdfSafeText(signedAt), textDirection: pw.TextDirection.ltr, textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 7)),
    ],
  );
}

class ReportPdfTheme {
  ReportPdfTheme(this.settings, {this.logo, required this.latinRegular, required this.latinBold});

  final AppCustomizer settings;
  final pw.ImageProvider? logo;
  final pw.Font latinRegular;
  final pw.Font latinBold;

  static Future<ReportPdfTheme> load() async {
    final settings = AppCustomizer.instance;
    await settings.load();
    final organizationBranding = await OrganizationBrandingStore.instance.forSession();
    if (settings.reportCompanyName.trim().isEmpty || settings.reportCompanyName == 'مؤسسة الشاعري للتجارة العامة') {
      settings.reportCompanyName = organizationBranding.name;
    }
    pw.ImageProvider? logo;
    // الشعار اختياري صراحةً. لا نستخدم شعار المؤسسة المشترك كـ fallback؛
    // حتى يبقى حذف الشعار من إعدادات الهوية محترمًا في ملفات PDF الجديدة.
    final url = settings.reportLogoUrl.trim();
    if (url.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          logo = pw.MemoryImage(response.bodyBytes);
        }
      } catch (_) {}
    }
    if (logo == null) {
      try {
        final data = await rootBundle.load('assets/images/alshaeri-official-logo.png');
        logo = pw.MemoryImage(data.buffer.asUint8List());
      } catch (_) {}
    }
    final latinRegular = await ReportPdfTheme.latinRegularFont();
    final latinBold = await ReportPdfTheme.latinBoldFont();
    return ReportPdfTheme(settings, logo: logo, latinRegular: latinRegular, latinBold: latinBold);
  }

  static final officialNavy = PdfColor.fromHex('#004A87');
  static final officialLightBlue = PdfColor.fromHex('#E5F2FF');
  static final officialGold = PdfColor.fromHex('#D9A52B');
  static final officialBorder = PdfColor.fromHex('#6EA6D8');

  PdfColor get primary => officialNavy;
  PdfColor get heading => officialNavy;
  double get fontSize => settings.reportFontSize;

  pw.Widget header(
    String title, {
    String? employee,
    String? branch,
    String? status,
    String? number,
    String? department,
    String? period,
    String? createdAt,
  }) => officialHeader(
    title,
    employee: employee,
    branch: branch,
    status: status,
    number: number,
    department: department,
    period: period,
    createdAt: createdAt,
  );

  pw.Widget officialHeader(
    String title, {
    String? employee,
    String? branch,
    String? status,
    String? number,
    String? department,
    String? period,
    String? createdAt,
    String? arabicOrganization,
    String englishOrganization = 'NEXORA',
  }) {
    final organization = reportPdfSafeText(arabicOrganization ?? settings.reportCompanyName);
    final metadata = <List<String>>[
      ['القسم', department ?? settings.reportBranchName],
      ['الموظف', employee ?? ''],
      ['الفرع', branch ?? ''],
      ['الحالة', status ?? ''],
      ['التاريخ', createdAt ?? (settings.reportShowExportDate ? DateTime.now().toLocal().toString().split('.').first : '')],
      ['الفترة', period ?? ''],
    ].where((item) => item[1].trim().isNotEmpty).toList();
    final metadataRows = <pw.TableRow>[];
    for (var index = 0; index < metadata.length; index += 2) {
      final right = metadata[index];
      final left = index + 1 < metadata.length ? metadata[index + 1] : const ['', ''];
      metadataRows.add(pw.TableRow(children: [_metadataCell(right[0], right[1]), _metadataCell(left[0], left[1])]));
    }
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: officialBorder, width: .8), borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(height: 5, color: officialNavy),
          pw.Container(height: 2, margin: const pw.EdgeInsets.only(top: 2, bottom: 8), color: officialGold),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Expanded(child: pw.Text(reportPdfSafeText(englishOrganization), textDirection: pw.TextDirection.ltr, textAlign: pw.TextAlign.left, style: pw.TextStyle(font: latinBold, fontSize: 10, color: officialNavy))),
              if (logo != null) pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 10), child: pw.Image(logo!, width: 58, height: 58, fit: pw.BoxFit.contain)) else pw.SizedBox(width: 78),
              pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [pw.Text(organization, textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: officialNavy)), if (settings.reportHeaderText.trim().isNotEmpty) pw.Text(reportPdfSafeText(settings.reportHeaderText), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, color: officialNavy))])),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Container(color: officialNavy, padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 8), child: pw.Text(reportPdfSafeText(title), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColors.white))),
          if (metadataRows.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 8), child: pw.Table(border: pw.TableBorder.all(color: officialBorder, width: .5), children: metadataRows)),
        ],
      ),
    );
  }

  pw.Widget _metadataCell(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5),
    child: pw.Row(children: [pw.Expanded(child: pw.Text(reportPdfSafeText(value), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8))), pw.SizedBox(width: 5), pw.Text('$label:', textDirection: pw.TextDirection.rtl, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: officialNavy))]),
  );

  pw.Widget sectionHeader(String title) => pw.Container(
    width: double.infinity,
    margin: const pw.EdgeInsets.only(top: 5, bottom: 6),
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: pw.BoxDecoration(color: officialNavy, borderRadius: pw.BorderRadius.circular(5)),
    child: pw.Text(reportPdfSafeText(title), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
  );

  pw.TableBorder get tableBorder => pw.TableBorder.all(color: officialBorder, width: .7);
  pw.BoxDecoration get tableHeaderDecoration => pw.BoxDecoration(color: officialLightBlue);

  pw.Widget footer([pw.Context? context, String? footerText]) => pw.Container(
    padding: const pw.EdgeInsets.only(top: 8),
    decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: officialGold, width: .8))),
    child: pw.Row(
      children: [
        pw.Expanded(child: pw.Text(_contactLine(), textDirection: pw.TextDirection.rtl, style: const pw.TextStyle(fontSize: 7))),
        pw.Expanded(child: pw.Text('${context == null ? '' : 'صفحة ${context.pageNumber} من ${context.pagesCount}'}\n${reportPdfSafeText(footerText ?? settings.reportFooterText)}', textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 7, color: officialNavy))),
        pw.Expanded(child: pw.Text(reportPdfSafeText(settings.reportCompanyName), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 7, color: officialNavy))),
      ],
    ),
  );

  String _contactLine() {
    final values = <String>[];
    if (settings.reportPhone.trim().isNotEmpty) values.add('الهاتف: ${settings.reportPhone.trim()}');
    if (settings.reportEmail.trim().isNotEmpty) values.add('البريد: ${settings.reportEmail.trim()}');
    if (settings.reportAddress.trim().isNotEmpty) values.add('العنوان: ${settings.reportAddress.trim()}');
    return reportPdfSafeText(values.join(' | '));
  }

  Future<Uint8List> buildDesignerPreviewPdf() async {
    final regular = await regularFont();
    final boldFontValue = await boldFont();
    final latin = await latinRegularFont();
    final latinBold = await latinBoldFont();
    final document = pw.Document(
      theme: pw.ThemeData.withFont(
        base: regular,
        bold: boldFontValue,
        fontFallback: [latin, latinBold],
      ),
    );
    final pageWidth = PdfPageFormat.a4.width;
    final pageHeight = PdfPageFormat.a4.height;
    final keys = <String>[
      'logo',
      ...settings.reportHeaderOrder,
      'signature',
      'footer',
      ...settings.reportCustomElements.keys,
    ];

    Map<String, double> positionFor(String key, int index) {
      if (settings.reportCustomElements.containsKey(key) || settings.reportElementPositions.containsKey(key)) {
        return settings.reportElementPosition(key);
      }
      if (key == 'logo') return {'left': .06, 'top': .04, 'width': .18, 'height': .11};
      return {'left': .08, 'top': (.04 + ((index + 1) * .055)).clamp(.02, .72).toDouble(), 'width': .84, 'height': .045};
    }

    String valueFor(String key) {
      final custom = settings.reportCustomElements[key];
      if (custom != null) return '${custom['text'] ?? ''}';
      switch (key) {
        case 'company': return settings.reportCompanyName;
        case 'branchName': return settings.reportBranchName;
        case 'phone': return settings.reportPhone.isEmpty ? '' : 'الهاتف: ${settings.reportPhone}';
        case 'email': return settings.reportEmail.isEmpty ? '' : 'البريد الإلكتروني: ${settings.reportEmail}';
        case 'address': return settings.reportAddress.isEmpty ? '' : 'العنوان: ${settings.reportAddress}';
        case 'headerText': return settings.reportHeaderText;
        case 'title': return 'تقرير المهمة';
        case 'employee': return settings.reportShowEmployee ? 'الموظف: أحمد محمد' : '';
        case 'taskBranch': return settings.reportShowBranch ? 'الفرع: الفرع الرئيسي' : '';
        case 'status': return settings.reportShowStatus ? 'الحالة: مكتملة' : '';
        case 'number': return settings.reportShowNumber ? 'رقم التقرير: 0001' : '';
        case 'exportDate': return settings.reportShowExportDate ? 'تاريخ التصدير: ${DateTime.now().toLocal().toString().split('.').first}' : '';
        case 'signature': return settings.reportShowSignature ? 'التوقيع: __________________' : '';
        case 'footer': return settings.reportShowFooter ? settings.reportFooterText : '';
        default: return '';
      }
    }

    pw.Widget textElement(String key, int index) {
      final custom = settings.reportCustomElements[key];
      if (custom?['visible'] == false) return pw.SizedBox();
      final position = positionFor(key, index);
      final layout = settings.reportHeaderLayout(key);
      final size = custom != null
          ? (custom['size'] is num ? (custom['size'] as num).toDouble() : 12.0)
          : (layout['size'] is num ? (layout['size'] as num).toDouble() : 12.0);
      final colorValue = custom?['color'] is num
          ? (custom!['color'] as num).toInt()
          : layout['color'] is num
              ? (layout['color'] as num).toInt()
              : key == 'title'
                  ? settings.reportHeadingColor
                  : settings.reportPrimaryColor;
      final alignValue = custom?['align'] ?? layout['align'];
      final textAlign = alignValue == 'left' ? pw.TextAlign.left : alignValue == 'center' ? pw.TextAlign.center : pw.TextAlign.right;
      final isBold = custom?['bold'] is bool ? custom!['bold'] as bool : layout['bold'] is bool ? layout['bold'] as bool : key == 'company' || key == 'title';
      final value = reportPdfSafeText(valueFor(key)).trim();
      if (value.isEmpty) return pw.SizedBox();
      return pw.Positioned(
        left: (position['left']! * pageWidth).toDouble(),
        top: (position['top']! * pageHeight).toDouble(),
        child: pw.SizedBox(
          width: (position['width']! * pageWidth).toDouble(),
          height: (position['height']! * pageHeight).toDouble(),
          child: pw.Container(
            alignment: alignValue == 'left' ? pw.Alignment.centerLeft : alignValue == 'center' ? pw.Alignment.center : pw.Alignment.centerRight,
            child: pw.Text(value, textDirection: pw.TextDirection.rtl, textAlign: textAlign, style: pw.TextStyle(font: isBold ? boldFontValue : regular, fontSize: size, color: PdfColor.fromInt(colorValue))),
          ),
        ),
      );
    }

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.Container(
                color: PdfColors.white,
                child: pw.Container(
                  margin: const pw.EdgeInsets.all(18),
                  decoration: pw.BoxDecoration(
                    color: settings.reportHeaderStyle == 'minimal' ? PdfColors.white : PdfColor.fromHex('#EAF4F0'),
                    border: settings.reportHeaderStyle == 'boxed' ? pw.Border.all(color: primary, width: .8) : null,
                  ),
                ),
              ),
            ),
            for (var index = 0; index < keys.length; index++)
              if (keys[index] == 'logo' && logo != null)
                pw.Positioned(
                  left: (positionFor(keys[index], index)['left']! * pageWidth).toDouble(),
                  top: (positionFor(keys[index], index)['top']! * pageHeight).toDouble(),
                  child: pw.SizedBox(
                    width: (positionFor(keys[index], index)['width']! * pageWidth).toDouble(),
                    height: (positionFor(keys[index], index)['height']! * pageHeight).toDouble(),
                    child: pw.Image(logo!, fit: pw.BoxFit.contain),
                  ),
                )
              else if (keys[index] != 'logo')
                textElement(keys[index], index),
            pw.Positioned(
              left: (.06 * pageWidth).toDouble(),
              top: (.56 * pageHeight).toDouble(),
              child: pw.SizedBox(
                width: (.88 * pageWidth).toDouble(),
                height: (.30 * pageHeight).toDouble(),
                child: pw.Table.fromTextArray(
                headers: const ['الوقت', 'المهمة والبيان', 'المخرج المطلوب', 'الحالة'],
                data: const [
                  ['08:00', 'مهمة حالية', 'لا يوجد', 'جديدة'],
                  ['—', 'مهمة استثنائية', 'لا يوجد', 'جديدة'],
                ],
                headerStyle: pw.TextStyle(font: boldFontValue, fontSize: 9, color: primary),
                cellStyle: pw.TextStyle(font: regular, fontSize: 8),
                headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#EAF1EF')),
                border: tableBorder,
                cellAlignment: pw.Alignment.centerRight,
                cellPadding: const pw.EdgeInsets.all(5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return document.save();
  }

  static Future<pw.Font> regularFont() async => pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
  static Future<pw.Font> boldFont() async => pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'));
  static Future<pw.Font> latinRegularFont() async => pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
  static Future<pw.Font> latinBoldFont() async => pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));

  static Future<pw.ThemeData> pdfTheme({pw.Font? base, pw.Font? bold}) async {
    final regular = base ?? await regularFont();
    final arabicBold = bold ?? await ReportPdfTheme.boldFont();
    final latin = await latinRegularFont();
    final latinBold = await latinBoldFont();
    return pw.ThemeData.withFont(base: regular, bold: arabicBold, fontFallback: [latin, latinBold]);
  }
}
