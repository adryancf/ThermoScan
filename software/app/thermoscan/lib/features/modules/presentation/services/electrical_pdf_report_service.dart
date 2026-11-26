import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:thermoscan/core/utils/date_formatter.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';

/// Generates a dedicated, professional English-only A4 PDF report for
/// continuous electrical monitoring (INA228) of a ThermoScan PV module/string.
class ElectricalPdfReportService {
  ElectricalPdfReportService._();

  static final PdfColor _primary = PdfColor.fromHex('#0B4F6C');
  static final PdfColor _accent = PdfColor.fromHex('#19B5D6');
  static final PdfColor _dark = PdfColor.fromHex('#0F172A');
  static final PdfColor _muted = PdfColor.fromHex('#475569');
  static final PdfColor _border = PdfColor.fromHex('#CBD5E1');
  static final PdfColor _surface = PdfColor.fromHex('#F8FAFC');
  static final PdfColor _white = PdfColors.white;

  static String rangeDisplayLabel(String range) {
    switch (range.toLowerCase()) {
      case '1h':
        return 'Last 1 Hour';
      case '24h':
        return 'Last 24 Hours';
      case '7d':
        return 'Last 7 Days';
      case '30d':
        return 'Last 30 Days';
      case 'all':
        return 'All Time (Lifetime)';
      default:
        return range.toUpperCase();
    }
  }

  static String _sanitizeLatin1(String input) {
    final normalized = input
        .replaceAll('\u2014', '-')
        .replaceAll('\u2013', '-')
        .replaceAll('\u2018', "'")
        .replaceAll('\u2019', "'")
        .replaceAll('\u201C', '"')
        .replaceAll('\u201D', '"')
        .replaceAll('\u2022', '*')
        .replaceAll('\u00B7', '|');
    final buf = StringBuffer();
    for (final rune in normalized.runes) {
      if ((rune >= 0x20 && rune <= 0x7E) || (rune >= 0xA0 && rune <= 0xFF)) {
        buf.writeCharCode(rune);
      }
    }
    return buf.toString();
  }

  static Future<Uint8List> buildReportBytes({
    required PvModule module,
    required PowerReadingsSeries series,
    required List<PowerReadingItem> recentReadings,
    String? generatedBy,
  }) async {
    final safeModuleName = _sanitizeLatin1(module.name);
    final safeGeneratedBy =
        generatedBy != null ? _sanitizeLatin1(generatedBy) : null;
    final doc = pw.Document(
      title: 'ThermoScan Electrical Report - $safeModuleName',
      author: (safeGeneratedBy != null && safeGeneratedBy.isNotEmpty)
          ? safeGeneratedBy
          : 'ThermoScan',
    );

    final generatedAt = DateTime.now().toUtc();
    final scopeLabel = series.panelIndex != null
        ? 'Panel ${series.panelIndex}'
        : (module.panelCount != null && module.panelCount! > 1
            ? 'All Panels (${module.panelCount}-panel string)'
            : 'Panel 1');
    final rangeLabel = rangeDisplayLabel(series.range);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 30, 32, 34),
        header: (ctx) => _buildHeader(
          module: module,
          rangeLabel: rangeLabel,
          scopeLabel: scopeLabel,
          generatedAt: generatedAt,
        ),
        footer: (ctx) => _buildFooter(ctx, generatedBy),
        build: (ctx) => [
          pw.SizedBox(height: 14),
          _buildKpiStrip(series.summary),
          pw.SizedBox(height: 16),
          _buildSectionTitle('Power Output Trend (W)'),
          pw.SizedBox(height: 6),
          _buildVectorChartCard(series),
          pw.SizedBox(height: 16),
          _buildSectionTitle(
            'Recent Electrical Readings (${math.min(recentReadings.length, 60)} of ${series.summary.totalReadings} samples)',
          ),
          pw.SizedBox(height: 6),
          _buildReadingsTable(
            readings: recentReadings,
            showPanelColumn:
                series.panelIndex == null && (module.panelCount ?? 1) > 1,
          ),
        ],
      ),
    );

    return doc.save();
  }

  static Future<void> shareOrPrintReport({
    required PvModule module,
    required PowerReadingsSeries series,
    required List<PowerReadingItem> recentReadings,
    String? generatedBy,
  }) async {
    final bytes = await buildReportBytes(
      module: module,
      series: series,
      recentReadings: recentReadings,
      generatedBy: generatedBy,
    );
    final safeName = module.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final filename =
        'thermoscan_electrical_${safeName.isEmpty ? "module" : safeName}_${series.range}.pdf';
    await Printing.sharePdf(
      bytes: bytes,
      filename: filename,
    );
  }

  static pw.Widget _buildHeader({
    required PvModule module,
    required String rangeLabel,
    required String scopeLabel,
    required DateTime generatedAt,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: _primary, width: 1.5),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'THERMOSCAN | ELECTRICAL TELEMETRY REPORT',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: _primary,
                    letterSpacing: 0.8,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  _sanitizeLatin1(module.name),
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: _dark,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'MAC: ${_sanitizeLatin1(module.macAddress)}   |   Scope: $scopeLabel   |   Period: $rangeLabel',
                  style: pw.TextStyle(fontSize: 8.5, color: _muted),
                ),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'Generated',
                style: pw.TextStyle(fontSize: 7.5, color: _muted),
              ),
              pw.Text(
                AppDateFormatter.formatDateTimeShort(generatedAt.toIso8601String()),
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                  color: _dark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(pw.Context ctx, String? generatedBy) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _border, width: 0.7)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              generatedBy != null && _sanitizeLatin1(generatedBy).isNotEmpty
                  ? 'ThermoScan Continuous Electrical Telemetry | Exported by ${_sanitizeLatin1(generatedBy)}'
                  : 'ThermoScan Continuous Electrical Telemetry',
              style: pw.TextStyle(fontSize: 7.5, color: _muted),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Text(
            'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: pw.TextStyle(fontSize: 7.5, color: _muted),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSectionTitle(String title) {
    return pw.Text(
      title,
      style: pw.TextStyle(
        fontSize: 11,
        fontWeight: pw.FontWeight.bold,
        color: _dark,
      ),
    );
  }

  static pw.Widget _buildKpiStrip(PowerSeriesSummary summary) {
    return pw.Row(
      children: [
        _buildKpiBox('Peak Power', formatElectricalPower(summary.peakPowerW),
            highlight: true),
        pw.SizedBox(width: 8),
        _buildKpiBox('Average Power', formatElectricalPower(summary.avgPowerW)),
        pw.SizedBox(width: 8),
        _buildKpiBox(
            'Average Voltage', formatElectricalVoltage(summary.avgVoltageV)),
        pw.SizedBox(width: 8),
        _buildKpiBox(
            'Average Current', formatElectricalCurrent(summary.avgCurrentA)),
        pw.SizedBox(width: 8),
        _buildKpiBox('Samples', summary.totalReadings.toString()),
      ],
    );
  }

  static pw.Widget _buildKpiBox(String label, String value,
      {bool highlight = false}) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: pw.BoxDecoration(
          color: highlight ? PdfColor.fromHex('#EFF6FA') : _surface,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          border: pw.Border.all(
            color: highlight ? _primary : _border,
            width: highlight ? 1.0 : 0.7,
          ),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(fontSize: 7.5, color: _muted),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 11.5,
                fontWeight: pw.FontWeight.bold,
                color: highlight ? _primary : _dark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildVectorChartCard(PowerReadingsSeries series) {
    final validPoints = series.points
        .where((p) => p.powerW != null && p.powerW!.isFinite)
        .toList();
    if (validPoints.isEmpty) {
      return pw.Container(
        height: 110,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          color: _surface,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          border: pw.Border.all(color: _border, width: 0.7),
        ),
        child: pw.Text(
          'No valid power data points available for this period.',
          style: pw.TextStyle(fontSize: 9, color: _muted),
        ),
      );
    }

    double maxW = 0.0;
    for (final p in validPoints) {
      if (p.powerW! > maxW) maxW = p.powerW!;
    }
    final topW = maxW <= 0 ? 1.0 : maxW * 1.12;

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: _border, width: 0.7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Peak scale: ${formatElectricalPower(topW)}',
                style: pw.TextStyle(fontSize: 7.5, color: _muted),
              ),
              pw.Text(
                '${validPoints.length} plotted intervals',
                style: pw.TextStyle(fontSize: 7.5, color: _muted),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.SizedBox(
            height: 120,
            width: double.infinity,
            child: pw.CustomPaint(
              size: const PdfPoint(480, 120),
              painter: (PdfGraphics canvas, PdfPoint size) {
                const padL = 6.0;
                const padR = 6.0;
                const padT = 6.0;
                const padB = 6.0;
                final w = math.max(1.0, size.x - padL - padR);
                final h = math.max(1.0, size.y - padT - padB);

                // Horizontal grid lines
                canvas
                  ..setStrokeColor(_border)
                  ..setLineWidth(0.5);
                for (var i = 0; i <= 3; i++) {
                  final y = padB + (i / 3.0) * h;
                  canvas
                    ..moveTo(padL, y)
                    ..lineTo(padL + w, y)
                    ..strokePath();
                }

                // Plot polyline
                canvas
                  ..setStrokeColor(_primary)
                  ..setLineWidth(1.6);
                if (validPoints.length == 1) {
                  final x = padL + w / 2;
                  final y = padB +
                      (validPoints[0].powerW!.clamp(0.0, topW) / topW) * h;
                  canvas
                    ..setFillColor(_accent)
                    ..drawEllipse(x, y, 2.5, 2.5)
                    ..fillPath();
                } else {
                  for (var i = 0; i < validPoints.length; i++) {
                    final x =
                        padL + (i / (validPoints.length - 1)) * w;
                    final y = padB +
                        (validPoints[i].powerW!.clamp(0.0, topW) / topW) * h;
                    if (i == 0) {
                      canvas.moveTo(x, y);
                    } else {
                      canvas.lineTo(x, y);
                    }
                  }
                  canvas.strokePath();
                }
              },
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                AppDateFormatter.formatDateTimeShort(
                  validPoints.first.bucketAt.toIso8601String(),
                ),
                style: pw.TextStyle(fontSize: 7.5, color: _muted),
              ),
              pw.Text(
                AppDateFormatter.formatDateTimeShort(
                  validPoints.last.bucketAt.toIso8601String(),
                ),
                style: pw.TextStyle(fontSize: 7.5, color: _muted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildReadingsTable({
    required List<PowerReadingItem> readings,
    required bool showPanelColumn,
  }) {
    if (readings.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: _surface,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          border: pw.Border.all(color: _border, width: 0.7),
        ),
        child: pw.Text(
          'No electrical readings available in this period.',
          style: pw.TextStyle(fontSize: 9, color: _muted),
        ),
      );
    }

    final headers = <String>[
      'Timestamp',
      if (showPanelColumn) 'Panel',
      'Voltage',
      'Current',
      'Power',
    ];

    final rows = readings.take(60).map((r) {
      return <String>[
        AppDateFormatter.formatDateTimeShort(r.measuredAt),
        if (showPanelColumn) 'Panel ${r.panelIndex}',
        formatElectricalVoltage(r.voltageV),
        formatElectricalCurrent(r.currentA),
        formatElectricalPower(r.powerW),
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: pw.TextStyle(
        fontSize: 8.5,
        fontWeight: pw.FontWeight.bold,
        color: _white,
      ),
      headerDecoration: pw.BoxDecoration(color: _primary),
      cellStyle: pw.TextStyle(fontSize: 8, color: _dark),
      rowDecoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _border, width: 0.4)),
      ),
      oddRowDecoration: pw.BoxDecoration(
        color: _surface,
        border: pw.Border(bottom: pw.BorderSide(color: _border, width: 0.4)),
      ),
      cellAlignment: pw.Alignment.centerLeft,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    );
  }
}
