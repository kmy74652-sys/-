import 'dart:typed_data';

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
    return ReportPdfTheme(settings, logo: logo);
  }

  PdfColor get primary => PdfColor.fromInt(settings.reportPrimaryColor);
  PdfColor get heading => PdfColor.fromInt(settings.reportHeadingColor);
  double get fontSize => settings.reportFontSize;

  pw.Widget header(String title, {String? employee, String? branch, String? status, String? number}) {
    final defaultOrder = const ['company', 'branchName', 'phone', 'email', 'address', 'headerText', 'title', 'employee', 'taskBranch', 'status', 'number', 'exportDate'];
    final order = <String>[...settings.reportHeaderOrder, ...defaultOrder.where((key) => !settings.reportHeaderOrder.contains(key))];
    final content = <pw.Widget>[];
    pw.Widget line(String key, String value, {double size = 10, bool bold = false, PdfColor? color, String? alignOverride, bool? boldOverride}) {
      final layout = settings.reportHeaderLayout(key);
      final selectedAlign = alignOverride ?? layout['align'];
      final align = selectedAlign == 'left' ? pw.TextAlign.left : selectedAlign == 'center' ? pw.TextAlign.center : pw.TextAlign.right;
      final configuredSize = settings.reportHeaderLayouts.containsKey(key) ? (layout['size'] as num).toDouble() : size;
      final configuredColor = settings.reportHeaderLayouts.containsKey(key) && layout['color'] is num
          ? PdfColor.fromInt((layout['color'] as num).toInt())
          : color;
      final configuredBold = boldOverride ?? (settings.reportHeaderLayouts.containsKey(key) && layout['bold'] is bool
          ? layout['bold'] as bool
          : bold);
      final position = settings.reportElementPositions[key];
      final x = position == null ? (layout['x'] as num).toDouble() : (position['left'] ?? 0) * 100;
      final y = position == null ? (layout['y'] as num).toDouble() : (position['top'] ?? 0) * 100;
      return pw.Container(
        margin: pw.EdgeInsets.only(left: x > 0 ? x : 0, right: x < 0 ? -x : 0, top: y > 0 ? y : 0, bottom: y < 0 ? -y : 0),
        child: pw.Text(reportPdfSafeText(value), textDirection: pw.TextDirection.rtl, textAlign: align, style: pw.TextStyle(fontSize: configuredSize, fontWeight: configuredBold ? pw.FontWeight.bold : pw.FontWeight.normal, color: configuredColor)),
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
    for (final entry in settings.reportCustomElements.entries) {
      final custom = entry.value;
      if (custom['visible'] == false || '${custom['type'] ?? 'text'}' == 'logo') continue;
      final text = '${custom['text'] ?? ''}'.trim();
      if (text.isEmpty) continue;
      final size = (custom['size'] is num ? (custom['size'] as num).toDouble() : 12).clamp(7, 32).toDouble();
      final color = PdfColor.fromInt(custom['color'] is num ? (custom['color'] as num).toInt() : settings.reportHeadingColor);
      content.add(line(entry.key, text, size: size, color: color, alignOverride: '${custom['align'] ?? ''}', boldOverride: custom['bold'] is bool ? custom['bold'] as bool : null));
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

  pw.Widget footer() => pw.Column(children: [
        if (settings.reportShowSignature) pw.Padding(padding: const pw.EdgeInsets.only(top: 12), child: pw.Text('التوقيع: __________________', textAlign: pw.TextAlign.right, textDirection: pw.TextDirection.rtl, style: pw.TextStyle(fontSize: 9, color: heading))),
        if (settings.reportShowFooter && settings.reportFooterText.trim().isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 12), child: pw.Text(reportPdfSafeText(settings.reportFooterText), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl, style: pw.TextStyle(fontSize: 8, color: heading))),
      ]);

  Future<Uint8List> buildDesignerPreviewPdf() async {
    final document = pw.Document();
    final regular = await regularFont();
    final boldFontValue = await boldFont();
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
}
