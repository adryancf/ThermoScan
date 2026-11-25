import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:thermoscan/core/utils/date_formatter.dart';
import 'package:thermoscan/features/modules/domain/inspection_routine_bundle.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/widgets/thermal_panorama_painter.dart';

/// Input payload for a single inspection section inside the PDF report.
class PdfInspectionEntry {
  const PdfInspectionEntry({
    required this.bundle,
    required this.routineMeasurements,
    this.verificationMeasurements = const [],
    this.restoredMeasurements = const [],
    this.usePostCleaningView = true,
    this.focusedPanelIndex,
  });

  final InspectionRoutineBundle bundle;
  final List<ModuleMeasurement> routineMeasurements;
  final List<ModuleMeasurement> verificationMeasurements;
  final List<ModuleMeasurement> restoredMeasurements;
  final bool usePostCleaningView;
  final int? focusedPanelIndex;

  bool get hasPostCleaning =>
      verificationMeasurements.isNotEmpty || bundle.hasPostCleaning;

  List<ModuleMeasurement> get displayMeasurements {
    if (usePostCleaningView && restoredMeasurements.isNotEmpty) {
      return restoredMeasurements;
    }
    if (routineMeasurements.isNotEmpty) {
      return routineMeasurements;
    }
    if (bundle.restoredMeasurements.isNotEmpty) {
      return bundle.restoredMeasurements;
    }
    return bundle.routineMeasurements;
  }
}

class _PanelBreakdownRow {
  const _PanelBreakdownRow({
    required this.panelIndex,
    required this.frameCount,
    this.baselineC,
    this.peakC,
    this.maxDeltaC,
    required this.electrical,
  });

  final int panelIndex;
  final int frameCount;
  final double? baselineC;
  final double? peakC;
  final double? maxDeltaC;
  final ElectricalSummary electrical;
}

class _InspectionMetrics {
  const _InspectionMetrics({
    required this.dateLabel,
    required this.shortId,
    required this.statusLabel,
    required this.statusTone,
    required this.frameCount,
    required this.expectedFrames,
    required this.peakC,
    required this.minC,
    required this.baselineC,
    required this.maxDeltaC,
    required this.electrical,
    required this.panelRows,
    required this.hotspotTotal,
    required this.hotspotCleared,
    required this.hotspotUnresolved,
    required this.washCount,
    required this.totalWashDurationSec,
    required this.isPostCleaningView,
    required this.panorama,
  });

  final String dateLabel;
  final String shortId;
  final String statusLabel;
  final String statusTone; // 'success' | 'warning' | 'error' | 'primary'
  final int frameCount;
  final int? expectedFrames;
  final double? peakC;
  final double? minC;
  final double? baselineC;
  final double? maxDeltaC;
  final ElectricalSummary electrical;
  final List<_PanelBreakdownRow> panelRows;
  final int hotspotTotal;
  final int hotspotCleared;
  final int hotspotUnresolved;
  final int washCount;
  final double totalWashDurationSec;
  final bool isPostCleaningView;
  final ThermalPanoramaData panorama;
}

/// Generates professional, technical, English-only A4 PDF inspection reports
/// for one or multiple inspections of a ThermoScan PV module/string.
class ThermalPdfReportService {
  ThermalPdfReportService._();

  static final PdfColor _primary = PdfColor.fromHex('#0B4F6C');
  static final PdfColor _dark = PdfColor.fromHex('#0F172A');
  static final PdfColor _muted = PdfColor.fromHex('#475569');
  static final PdfColor _border = PdfColor.fromHex('#CBD5E1');
  static final PdfColor _surface = PdfColor.fromHex('#F8FAFC');
  static final PdfColor _white = PdfColors.white;

  static final PdfColor _successFg = PdfColor.fromHex('#15803D');
  static final PdfColor _successBg = PdfColor.fromHex('#DCFCE7');
  static final PdfColor _warningFg = PdfColor.fromHex('#B45309');
  static final PdfColor _warningBg = PdfColor.fromHex('#FEF3C7');
  static final PdfColor _errorFg = PdfColor.fromHex('#B91C1C');
  static final PdfColor _errorBg = PdfColor.fromHex('#FEE2E2');
  static final PdfColor _primarySoft = PdfColor.fromHex('#E0F2FE');

  static final List<PdfColor> _spectrumColors = [
    PdfColor.fromHex('#1E4FD8'),
    PdfColor.fromHex('#19B5D6'),
    PdfColor.fromHex('#34D399'),
    PdfColor.fromHex('#FFD43B'),
    PdfColor.fromHex('#FF8A1F'),
    PdfColor.fromHex('#E5322D'),
  ];

  /// Renders the high-resolution thermal panorama bitmap offscreen using the
  /// exact same [ThermalPanoramaPainter] used in the live Flutter UI.
  static Future<Uint8List?> renderPanoramaPng({
    required ThermalPanoramaData panorama,
    List<ConfirmedAnomaly> markers = const [],
    double width = 1120,
    double height = 280,
  }) async {
    if (!panorama.hasAnyThermalMatrix || panorama.gridColumns <= 0) {
      return null;
    }

    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

      // Dark radiometric studio backdrop
      final bgPaint = Paint()..color = const Color(0xFF0B1220);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, width, height),
          const Radius.circular(14),
        ),
        bgPaint,
      );

      const topPadding = 34.0;
      const bottomPadding = 26.0;
      const sidePadding = 18.0;
      final mapRect = Rect.fromLTWH(
        sidePadding,
        topPadding,
        width - sidePadding * 2,
        height - topPadding - bottomPadding,
      );

      // Top panel header pills
      final domainSpan = panorama.domainSpanCm;
      if (domainSpan > 0 && panorama.panelBounds.isNotEmpty) {
        final pxPerCm = mapRect.width / domainSpan;
        for (final bound in panorama.panelBounds) {
          if (panorama.focusedPanelIndex != null &&
              panorama.focusedPanelIndex != bound.panelIndex) {
            continue;
          }
          final left =
              mapRect.left + (bound.startXCm - panorama.minDomainX) * pxPerCm;
          final right =
              mapRect.left + (bound.endXCm - panorama.minDomainX) * pxPerCm;
          final centerX = (left + right) / 2;
          final label =
              'PANEL ${bound.panelIndex} (${bound.startXCm.toStringAsFixed(0)}-${bound.endXCm.toStringAsFixed(0)} cm)';
          final tp = TextPainter(
            text: TextSpan(
              text: label,
              style: const TextStyle(
                color: Color(0xFFE2E8F0),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          final pillRect = RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(centerX, 17),
              width: tp.width + 18,
              height: 22,
            ),
            const Radius.circular(11),
          );
          canvas.drawRRect(
            pillRect,
            Paint()..color = const Color(0xFF1E3A5F),
          );
          tp.paint(
            canvas,
            Offset(centerX - tp.width / 2, 17 - tp.height / 2),
          );
        }
      }

      // Paint the exact thermal panorama matrix
      canvas.save();
      canvas.translate(mapRect.left, mapRect.top);
      canvas.clipRRect(
        RRect.fromRectAndRadius(
          Offset.zero & mapRect.size,
          const Radius.circular(6),
        ),
      );
      ThermalPanoramaPainter(panorama: panorama).paint(canvas, mapRect.size);

      // Draw active hotspot markers along X
      if (markers.isNotEmpty && domainSpan > 0) {
        final pxPerCm = mapRect.width / domainSpan;
        for (var i = 0; i < markers.length; i++) {
          final anom = markers[i];
          final mx = (anom.xPositionCm - panorama.minDomainX) * pxPerCm;
          if (mx < 0 || mx > mapRect.width) continue;
          final center = Offset(mx, mapRect.height * 0.24);
          canvas.drawCircle(
            center,
            13,
            Paint()..color = const Color(0xFFDC2626),
          );
          canvas.drawCircle(
            center,
            13,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.2,
          );
          final tp = TextPainter(
            text: TextSpan(
              text: 'H${i + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(
            canvas,
            Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
          );
        }
      }
      canvas.restore();

      // Bottom axis caption
      final axisCaption = TextPainter(
        text: TextSpan(
          text:
              'Range: ${panorama.minDomainX.toStringAsFixed(1)} to ${panorama.maxDomainX.toStringAsFixed(1)} cm  |  Step: 2.0 cm  |  Optical Rail FOV: ${ThermalCoverageInfo.stitchFovCm.toStringAsFixed(1)} cm (24x32 IR)',
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      axisCaption.paint(
        canvas,
        Offset(sidePadding, height - bottomPadding + 6),
      );

      final picture = recorder.endRecording();
      final image = await picture.toImage(width.round(), height.round());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Builds the complete A4 PDF document bytes for [module] and [entries].
  ///
  /// When [includeThermalImages] is true, offscreen high-resolution panorama
  /// PNGs are rendered for every inspection with valid thermal matrices.
  static Future<Uint8List> buildReportBytes({
    required PvModule module,
    required List<PdfInspectionEntry> entries,
    String? generatedByName,
    String? generatedByRole,
    DateTime? generatedAt,
    bool includeThermalImages = true,
  }) async {
    final now = (generatedAt ?? DateTime.now()).toLocal();
    final reportCode = _buildReportCode(module, now);
    final generatedLabel = AppDateFormatter.formatDateTime(
      now,
      includeYear: true,
      fallback: now.toIso8601String(),
    );

    final computedList = <_InspectionMetrics>[];
    final panoramaImages = <Uint8List?>[];

    for (final entry in entries) {
      final metrics = _computeInspectionMetrics(module, entry);
      computedList.add(metrics);

      if (includeThermalImages && metrics.panorama.hasAnyThermalMatrix) {
        final activeMarkers = _resolveActiveMarkers(entry);
        final png = await renderPanoramaPng(
          panorama: metrics.panorama,
          markers: activeMarkers,
        );
        panoramaImages.add(png);
      } else {
        panoramaImages.add(null);
      }
    }

    final doc = pw.Document(
      title: 'ThermoScan Radiometric Inspection Report - ${module.name}',
      author: generatedByName ?? 'ThermoScan Diagnostic System',
      creator: 'ThermoScan Mobile App',
    );

    final baseTheme = pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
      italic: pw.Font.helveticaOblique(),
      boldItalic: pw.Font.helveticaBoldOblique(),
    );

    // Page 1 (and overflow if multi-inspection summary is large):
    // Asset Specification + Executive Summary (when 2+ inspections)
    // OR directly Asset Specification + Inspection #1 (when 1 inspection).
    doc.addPage(
      pw.MultiPage(
        theme: baseTheme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 28),
        header: (ctx) => _buildPageHeader(
          reportCode: reportCode,
          generatedLabel: generatedLabel,
          moduleName: module.name,
        ),
        footer: (ctx) => _buildPageFooter(
          pageNumber: ctx.pageNumber,
          pagesCount: ctx.pagesCount,
          generatedByName: generatedByName,
          generatedByRole: generatedByRole,
        ),
        build: (ctx) {
          final widgets = <pw.Widget>[
            _buildAssetSpecificationSection(module),
            pw.SizedBox(height: 14),
          ];

          if (entries.length > 1) {
            widgets.addAll(
              _buildExecutiveSummaryWidgets(
                module: module,
                metricsList: computedList,
              ),
            );
          } else if (entries.length == 1) {
            widgets.addAll(
              _buildSingleInspectionWidgets(
                module: module,
                entry: entries.first,
                metrics: computedList.first,
                panoramaPng: panoramaImages.first,
                inspectionOrdinal: 1,
                totalInspections: 1,
              ),
            );
          } else {
            widgets.add(
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: _surface,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: _border),
                ),
                child: pw.Text(
                  'No inspection records were selected for this report.',
                  style: pw.TextStyle(fontSize: 10, color: _muted),
                ),
              ),
            );
          }

          return widgets;
        },
      ),
    );

    // For multi-inspection reports (2+), place each inspection's full detailed
    // breakdown on its own clean page(s), identical to a single-inspection export.
    if (entries.length > 1) {
      for (var i = 0; i < entries.length; i++) {
        doc.addPage(
          pw.MultiPage(
            theme: baseTheme,
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 28),
            header: (ctx) => _buildPageHeader(
              reportCode: reportCode,
              generatedLabel: generatedLabel,
              moduleName: module.name,
            ),
            footer: (ctx) => _buildPageFooter(
              pageNumber: ctx.pageNumber,
              pagesCount: ctx.pagesCount,
              generatedByName: generatedByName,
              generatedByRole: generatedByRole,
            ),
            build: (ctx) => _buildSingleInspectionWidgets(
              module: module,
              entry: entries[i],
              metrics: computedList[i],
              panoramaPng: panoramaImages[i],
              inspectionOrdinal: i + 1,
              totalInspections: entries.length,
            ),
          ),
        );
      }
    }

    return doc.save();
  }

  /// Generates the PDF and opens the native OS share/download sheet.
  static Future<void> shareOrSavePdf({
    required PvModule module,
    required List<PdfInspectionEntry> entries,
    String? generatedByName,
    String? generatedByRole,
  }) async {
    final bytes = await buildReportBytes(
      module: module,
      entries: entries,
      generatedByName: generatedByName,
      generatedByRole: generatedByRole,
      includeThermalImages: true,
    );

    final safeName = module.name
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final fileName =
        'ThermoScan_${safeName.isEmpty ? 'Module' : safeName}_$stamp.pdf';

    await Printing.sharePdf(bytes: bytes, filename: fileName);
  }

  static String _buildReportCode(PvModule module, DateTime now) {
    final ymd =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final suffix = module.id.length >= 4
        ? module.id.substring(0, 4).toUpperCase()
        : 'MOD';
    return 'TS-$ymd-$suffix';
  }

  static List<ConfirmedAnomaly> _resolveActiveMarkers(PdfInspectionEntry entry) {
    final anomalies = entry.bundle.confirmedAnomalies;
    if (anomalies.isEmpty) return const [];
    if (!entry.usePostCleaningView || !entry.hasPostCleaning) {
      return anomalies;
    }
    final clearedIds = entry.bundle.hotspotSummaries
        .where((s) => s.isCleared)
        .map((s) => s.anomaly.id)
        .toSet();
    return anomalies.where((a) => !clearedIds.contains(a.id)).toList();
  }

  static _InspectionMetrics _computeInspectionMetrics(
    PvModule module,
    PdfInspectionEntry entry,
  ) {
    final insp = entry.bundle.routineInspection;
    final displayMeas = entry.displayMeasurements;
    final dateIso = insp.finishedAt ??
        insp.startedAt ??
        (insp.scheduledFor.isNotEmpty ? insp.scheduledFor : insp.createdAt);
    final parsedDt = DateTime.tryParse(dateIso);
    final dateLabel = parsedDt != null
        ? AppDateFormatter.formatDateTime(
            parsedDt,
            includeYear: true,
            fallback: dateIso,
          )
        : (dateIso.isNotEmpty ? dateIso : 'N/A');

    final shortId = insp.id.length > 8
        ? insp.id.substring(0, 8).toUpperCase()
        : insp.id.toUpperCase();

    final panelBaselines = buildPanelBaselineMap(insp.panelResults);
    final fallbackBaseline = insp.baselineTemperatureC;
    final thresholdC = module.hotspotThresholdDeltaC;

    final panorama = ThermalPanoramaData.fromMeasurements(
      measurements: displayMeas,
      panelLengthCm: module.panelLengthCm,
      panelCount: module.panelCount,
      panelSpacingCm: module.panelSpacingCm,
      focusedPanelIndex: entry.focusedPanelIndex,
      baselineTempC: fallbackBaseline,
      panelBaselines: panelBaselines,
      hotspotDeltaThresholdC: thresholdC,
    );

    final peakC = displayMeas.isNotEmpty
        ? displayMeas.map((m) => m.maxTemperatureC).reduce(math.max)
        : panorama.maxValidTempC;
    final minC = panorama.minValidTempC;
    final maxDeltaC = computeMaxPerPanelDelta(
          measurements: displayMeas,
          panelBaselines: panelBaselines,
          fallbackBaseline: fallbackBaseline,
          module: module,
        ) ??
        ((peakC != null && fallbackBaseline != null)
            ? (peakC - fallbackBaseline)
            : null);

    final electrical = computeElectricalSummary(
      measurements: displayMeas,
      module: module,
      focusedPanelIndex: entry.focusedPanelIndex,
    );

    // Group measurements by panel for the per-panel breakdown table
    final panelCount =
        (module.panelCount != null && module.panelCount! > 0) ? module.panelCount! : 1;
    final panelLen =
        (module.panelLengthCm != null && module.panelLengthCm! > 0)
            ? module.panelLengthCm!
            : 100.0;
    final panelSpacing =
        (module.panelSpacingCm != null && module.panelSpacingCm! >= 0)
            ? module.panelSpacingCm!
            : 2.0;
    final byPanel = <int, List<ModuleMeasurement>>{};
    for (final m in displayMeas) {
      final pIdx = _resolvePanelIndex(
        m: m,
        panelCount: panelCount,
        panelLen: panelLen,
        panelSpacing: panelSpacing,
      );
      byPanel.putIfAbsent(pIdx, () => []).add(m);
    }

    final panelIndices = <int>{
      ...byPanel.keys,
      ...panelBaselines.keys,
    }.toList()
      ..sort();
    if (panelIndices.isEmpty) {
      for (var p = 1; p <= panelCount; p++) {
        panelIndices.add(p);
      }
    }

    final panelRows = <_PanelBreakdownRow>[];
    for (final p in panelIndices) {
      if (entry.focusedPanelIndex != null && entry.focusedPanelIndex != p) {
        continue;
      }
      final frames = byPanel[p] ?? const <ModuleMeasurement>[];
      final pBase = panelBaselines[p] ?? fallbackBaseline;
      final pPeak = frames.isNotEmpty
          ? frames.map((m) => m.maxTemperatureC).reduce(math.max)
          : null;
      final pDelta =
          (pPeak != null && pBase != null) ? (pPeak - pBase) : null;
      final pElec = computeElectricalSummary(
        measurements: frames,
        module: module,
        focusedPanelIndex: p,
      );
      panelRows.add(
        _PanelBreakdownRow(
          panelIndex: p,
          frameCount: frames.length,
          baselineC: pBase,
          peakC: pPeak,
          maxDeltaC: pDelta,
          electrical: pElec,
        ),
      );
    }

    final expectedFrames = (module.panelLengthCm != null &&
            module.panelLengthCm! > 0)
        ? ((module.panelLengthCm! / ThermalCoverageInfo.stepCm).ceil() + 1) *
            panelCount
        : null;

    // Outcome badge resolution
    final summaries = entry.bundle.hotspotSummaries;
    final hotspotTotal = summaries.isNotEmpty
        ? summaries.length
        : entry.bundle.confirmedAnomalies.length;
    final resolved = entry.bundle.resolvedCount;
    final resolvedLater = entry.bundle.resolvedLaterCount;
    final cleared = resolved + resolvedLater;
    final unresolved = entry.bundle.unresolvedCount;
    final pending = entry.bundle.pendingCount;

    final statusUpper = insp.status.toUpperCase();
    String statusLabel;
    String statusTone;
    if (statusUpper == 'CANCELLED') {
      statusLabel = 'ABORTED';
      statusTone = 'warning';
    } else if (statusUpper == 'FAILED') {
      statusLabel = 'FAILED';
      statusTone = 'error';
    } else if (statusUpper == 'IN_PROGRESS') {
      statusLabel = 'IN PROGRESS';
      statusTone = 'primary';
    } else if (summaries.isNotEmpty) {
      if (resolvedLater > 0 &&
          unresolved == 0 &&
          resolved == 0 &&
          pending == 0) {
        statusLabel = 'CLEARED IN LATER SCAN';
        statusTone = 'primary';
      } else if (cleared == hotspotTotal && hotspotTotal > 0) {
        statusLabel = hotspotTotal == 1
            ? 'HOTSPOT RESOLVED'
            : '$hotspotTotal/$hotspotTotal RESOLVED';
        statusTone = 'success';
      } else if (cleared > 0 && (unresolved > 0 || pending > 0)) {
        statusLabel = '$cleared/$hotspotTotal RESOLVED';
        statusTone = 'warning';
      } else if (unresolved > 0) {
        statusLabel = '$unresolved UNRESOLVED';
        statusTone = 'error';
      } else if (pending > 0) {
        statusLabel = 'VERIFICATION PENDING';
        statusTone = 'warning';
      } else {
        statusLabel = '$hotspotTotal HOTSPOT${hotspotTotal > 1 ? 'S' : ''}';
        statusTone = 'error';
      }
    } else if (hotspotTotal > 0) {
      statusLabel = '$hotspotTotal HOTSPOT${hotspotTotal > 1 ? 'S' : ''}';
      statusTone = 'error';
    } else {
      statusLabel = 'HEALTHY';
      statusTone = 'success';
    }

    double totalDurationSec = 0;
    for (final c in entry.bundle.cleanings) {
      totalDurationSec += c.durationSeconds ?? 0.0;
    }

    return _InspectionMetrics(
      dateLabel: dateLabel,
      shortId: shortId,
      statusLabel: statusLabel,
      statusTone: statusTone,
      frameCount: displayMeas.length,
      expectedFrames: expectedFrames,
      peakC: peakC,
      minC: minC,
      baselineC: fallbackBaseline,
      maxDeltaC: maxDeltaC,
      electrical: electrical,
      panelRows: panelRows,
      hotspotTotal: hotspotTotal,
      hotspotCleared: cleared,
      hotspotUnresolved: unresolved,
      washCount: entry.bundle.cleanings.length,
      totalWashDurationSec: totalDurationSec,
      isPostCleaningView: entry.usePostCleaningView && entry.hasPostCleaning,
      panorama: panorama,
    );
  }

  static int _resolvePanelIndex({
    required ModuleMeasurement m,
    required int panelCount,
    required double panelLen,
    required double panelSpacing,
  }) {
    if (m.panelIndex != null && m.panelIndex! > 0) {
      return m.panelIndex!;
    }
    if (panelCount <= 1) return 1;
    final x = m.xPositionCm;
    if (x <= 0) return 1;
    for (var p = 1; p <= panelCount; p++) {
      final start = (p - 1) * (panelLen + panelSpacing);
      final end = start + panelLen;
      if (x >= start && x <= end) return p;
      if (p < panelCount && x > end && x < start + panelLen + panelSpacing) {
        return x <= (end + panelSpacing / 2.0) ? p : p + 1;
      }
    }
    return panelCount;
  }

  static pw.Widget _buildPageHeader({
    required String reportCode,
    required String generatedLabel,
    required String moduleName,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 14),
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _primary, width: 1.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'THERMOSCAN',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: _primary,
                  letterSpacing: 1.2,
                ),
              ),
              pw.SizedBox(height: 1),
              pw.Text(
                'RADIOMETRIC PV INSPECTION REPORT  |  $moduleName',
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                  color: _muted,
                ),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'REPORT #$reportCode',
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                  color: _dark,
                ),
              ),
              pw.SizedBox(height: 1),
              pw.Text(
                'Generated: $generatedLabel',
                style: pw.TextStyle(fontSize: 7.5, color: _muted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPageFooter({
    required int pageNumber,
    required int pagesCount,
    String? generatedByName,
    String? generatedByRole,
  }) {
    final issuer = (generatedByName != null && generatedByName.isNotEmpty)
        ? 'Exported by $generatedByName${generatedByRole != null && generatedByRole.isNotEmpty ? ' ($generatedByRole)' : ''}'
        : 'ThermoScan Autonomous Diagnostic Engine';

    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _border, width: 0.75)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '$issuer  |  MLX90640 24x32 IR & INA228 Telemetry',
            style: pw.TextStyle(fontSize: 7.5, color: _muted),
          ),
          pw.Text(
            'Page $pageNumber of $pagesCount',
            style: pw.TextStyle(
              fontSize: 7.5,
              fontWeight: pw.FontWeight.bold,
              color: _dark,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildAssetSpecificationSection(PvModule module) {
    final panelCount = module.panelCount ?? 1;
    final lenStr = module.panelLengthCm != null
        ? '${module.panelLengthCm!.toStringAsFixed(1)} cm'
        : 'N/A';
    final widthStr = module.panelWidthCm != null
        ? '${module.panelWidthCm!.toStringAsFixed(1)} cm'
        : 'N/A';
    final gapStr = module.panelSpacingCm != null
        ? '${module.panelSpacingCm!.toStringAsFixed(1)} cm'
        : '0.0 cm';
    final totalRail = module.calculatedTotalLengthCm;
    final railStr =
        totalRail > 0 ? '${totalRail.toStringAsFixed(1)} cm' : 'N/A';
    final thresholdStr =
        '+${module.hotspotThresholdDeltaC.toStringAsFixed(1)} \u00B0C';
    final orientationStr =
        (module.tiltDeg != null || module.azimuthDeg != null)
            ? 'Tilt ${module.tiltDeg?.toStringAsFixed(0) ?? '-'} deg | Azimuth ${module.azimuthDeg?.toStringAsFixed(0) ?? '-'} deg'
            : 'Not configured';
    final locationStr = (module.latitude != null && module.longitude != null)
        ? '${module.latitude!.toStringAsFixed(5)}, ${module.longitude!.toStringAsFixed(5)}'
        : 'Not specified';

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _surface,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _border),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'ASSET & ARRAY SPECIFICATION',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: _primary,
                  letterSpacing: 0.6,
                ),
              ),
              _buildPillBadge(
                label: module.monitoringStatus.toUpperCase(),
                tone: module.monitoringStatus == 'active'
                    ? 'success'
                    : 'warning',
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(1.2),
              1: pw.FlexColumnWidth(1.2),
              2: pw.FlexColumnWidth(1.2),
            },
            children: [
              pw.TableRow(
                children: [
                  _buildMetaItem('Module Name', module.name),
                  _buildMetaItem('Robot MAC Address', module.macAddress),
                  _buildMetaItem('Location / GPS', locationStr),
                ],
              ),
              pw.TableRow(
                children: [
                  pw.SizedBox(height: 6),
                  pw.SizedBox(height: 6),
                  pw.SizedBox(height: 6),
                ],
              ),
              pw.TableRow(
                children: [
                  _buildMetaItem(
                    'Array Architecture',
                    '$panelCount panel${panelCount == 1 ? '' : 's'} ($lenStr x $widthStr)',
                  ),
                  _buildMetaItem(
                    'Rail & Gap Geometry',
                    'Rail $railStr | Gap $gapStr',
                  ),
                  _buildMetaItem(
                    'Diagnostic Rules',
                    'Hotspot >= $thresholdStr | Every ${module.inspectionIntervalDays}d',
                  ),
                ],
              ),
              pw.TableRow(
                children: [
                  pw.SizedBox(height: 6),
                  pw.SizedBox(height: 6),
                  pw.SizedBox(height: 6),
                ],
              ),
              pw.TableRow(
                children: [
                  _buildMetaItem('Solar Orientation', orientationStr),
                  _buildMetaItem(
                    'Water Tank Capacity',
                    '${module.reservoirNominalCapacityMl ?? 2000} mL',
                  ),
                  _buildMetaItem(
                    'Installer Technician',
                    module.installerName.isNotEmpty
                        ? module.installerName
                        : 'Assigned Team',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildMetaItem(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(right: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 6.8,
              fontWeight: pw.FontWeight.bold,
              color: _muted,
              letterSpacing: 0.3,
            ),
          ),
          pw.SizedBox(height: 1.5),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 8.8,
              fontWeight: pw.FontWeight.bold,
              color: _dark,
            ),
          ),
        ],
      ),
    );
  }

  static List<pw.Widget> _buildExecutiveSummaryWidgets({
    required PvModule module,
    required List<_InspectionMetrics> metricsList,
  }) {
    final maxPeak = metricsList
        .map((m) => m.peakC)
        .whereType<double>()
        .fold<double?>(null, (acc, v) => acc == null ? v : math.max(acc, v));
    final maxDelta = metricsList
        .map((m) => m.maxDeltaC)
        .whereType<double>()
        .fold<double?>(null, (acc, v) => acc == null ? v : math.max(acc, v));
    final totalHotspots =
        metricsList.fold<int>(0, (sum, m) => sum + m.hotspotTotal);
    final clearedHotspots =
        metricsList.fold<int>(0, (sum, m) => sum + m.hotspotCleared);
    final totalWashes =
        metricsList.fold<int>(0, (sum, m) => sum + m.washCount);
    final totalDurationSec =
        metricsList.fold<double>(0.0, (sum, m) => sum + m.totalWashDurationSec);
    final threshold = module.hotspotThresholdDeltaC;

    return [
      pw.Text(
        'EXECUTIVE SUMMARY (${metricsList.length} INSPECTIONS)',
        style: pw.TextStyle(
          fontSize: 10.5,
          fontWeight: pw.FontWeight.bold,
          color: _dark,
          letterSpacing: 0.5,
        ),
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        'Consolidated radiometric and cleaning overview across the selected inspection cycles. Individual full reports follow on the next pages.',
        style: pw.TextStyle(fontSize: 8, color: _muted),
      ),
      pw.SizedBox(height: 10),

      // 4 Executive KPI Cards
      pw.Row(
        children: [
          pw.Expanded(
            child: _buildKpiBox(
              label: 'MAX PEAK TEMP',
              value: maxPeak != null
                  ? '${maxPeak.toStringAsFixed(1)} \u00B0C'
                  : 'N/A',
              sublabel: 'Highest recorded frame',
              accentColor:
                  (maxDelta != null && maxDelta >= threshold) ? _errorFg : _dark,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: _buildKpiBox(
              label: 'MAX THERMAL DELTA',
              value: maxDelta != null
                  ? '${maxDelta >= 0 ? '+' : ''}${maxDelta.toStringAsFixed(1)} \u00B0C'
                  : 'N/A',
              sublabel: 'Threshold: +${threshold.toStringAsFixed(1)} \u00B0C',
              accentColor: (maxDelta != null && maxDelta >= threshold)
                  ? _errorFg
                  : _successFg,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: _buildKpiBox(
              label: 'HOTSPOTS CLEARED',
              value: totalHotspots > 0
                  ? '$clearedHotspots / $totalHotspots'
                  : '0 Detected',
              sublabel: totalHotspots > 0
                  ? 'Verified or cleared later'
                  : 'All scans healthy',
              accentColor: totalHotspots == 0 || clearedHotspots == totalHotspots
                  ? _successFg
                  : _warningFg,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: _buildKpiBox(
              label: 'WASHING CYCLES',
              value: '$totalWashes wash${totalWashes == 1 ? '' : 'es'}',
              sublabel: totalDurationSec > 0
                  ? 'Total duration: ${totalDurationSec.toStringAsFixed(1)} s'
                  : 'No wash actuated',
              accentColor: _primary,
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 12),

      // Comparative table across all selected inspections
      pw.TableHelper.fromTextArray(
        headerStyle: pw.TextStyle(
          fontSize: 7.8,
          fontWeight: pw.FontWeight.bold,
          color: _white,
        ),
        headerDecoration: pw.BoxDecoration(color: _primary),
        cellStyle: pw.TextStyle(fontSize: 7.8, color: _dark),
        oddRowDecoration: pw.BoxDecoration(color: _surface),
        border: pw.TableBorder.all(color: _border, width: 0.5),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        headers: const [
          '#',
          'Date & Time',
          'Verdict',
          'Peak',
          'Baseline',
          'Max dT',
          'Avg Power',
          'Hotspots',
          'Washes',
        ],
        data: [
          for (var i = 0; i < metricsList.length; i++)
            [
              '${i + 1}',
              metricsList[i].dateLabel,
              metricsList[i].statusLabel,
              metricsList[i].peakC != null
                  ? '${metricsList[i].peakC!.toStringAsFixed(1)} \u00B0C'
                  : 'N/A',
              metricsList[i].baselineC != null
                  ? '${metricsList[i].baselineC!.toStringAsFixed(1)} \u00B0C'
                  : 'N/A',
              metricsList[i].maxDeltaC != null
                  ? '${metricsList[i].maxDeltaC! >= 0 ? '+' : ''}${metricsList[i].maxDeltaC!.toStringAsFixed(1)} \u00B0C'
                  : 'N/A',
              metricsList[i].electrical.powerW != null
                  ? '${metricsList[i].electrical.powerW!.toStringAsFixed(2)} W'
                  : 'N/A',
              '${metricsList[i].hotspotTotal}',
              '${metricsList[i].washCount}',
            ],
        ],
      ),
    ];
  }

  static List<pw.Widget> _buildSingleInspectionWidgets({
    required PvModule module,
    required PdfInspectionEntry entry,
    required _InspectionMetrics metrics,
    required Uint8List? panoramaPng,
    required int inspectionOrdinal,
    required int totalInspections,
  }) {
    final threshold = module.hotspotThresholdDeltaC;
    final isDeltaElevated =
        metrics.maxDeltaC != null && metrics.maxDeltaC! >= threshold;

    final coverageStr = metrics.expectedFrames != null && metrics.expectedFrames! > 0
        ? '${metrics.frameCount}/${metrics.expectedFrames} frames (${((metrics.frameCount / metrics.expectedFrames!) * 100).clamp(0, 100).toStringAsFixed(0)}%)'
        : '${metrics.frameCount} frames';

    final titlePrefix = totalInspections > 1
        ? 'INSPECTION $inspectionOrdinal OF $totalInspections  |  '
        : 'INSPECTION DETAILS  |  ';

    final widgets = <pw.Widget>[
      // Inspection Section Banner
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: pw.BoxDecoration(
          color: _primarySoft,
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: _primary, width: 0.8),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    '$titlePrefix${metrics.dateLabel}',
                    style: pw.TextStyle(
                      fontSize: 10.5,
                      fontWeight: pw.FontWeight.bold,
                      color: _dark,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'ID: ${metrics.shortId}  |  Coverage: $coverageStr  |  View: ${metrics.isPostCleaningView ? 'After Cleaning (Fused Verification)' : 'Routine Pre-Cleaning Scan'}',
                    style: pw.TextStyle(fontSize: 7.6, color: _muted),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 8),
            _buildPillBadge(
              label: metrics.statusLabel,
              tone: metrics.statusTone,
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 10),

      // High-Res Thermal Panorama Image + Radiometric Color Scale
      if (panoramaPng != null) ...[
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(
            color: _white,
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(color: _border),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.ClipRRect(
                horizontalRadius: 5,
                verticalRadius: 5,
                child: pw.Image(
                  pw.MemoryImage(panoramaPng),
                  width: double.infinity,
                  height: 138,
                  fit: pw.BoxFit.fill,
                ),
              ),
              pw.SizedBox(height: 6),
              // Calibrated Radiometric Spectrum Bar
              pw.Row(
                children: [
                  for (final color in _spectrumColors)
                    pw.Expanded(
                      child: pw.Container(height: 5, color: color),
                    ),
                ],
              ),
              pw.SizedBox(height: 3),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Min: ${metrics.minC != null ? '${metrics.minC!.toStringAsFixed(1)} \u00B0C' : 'N/A'}',
                    style: pw.TextStyle(fontSize: 7.3, color: _muted),
                  ),
                  pw.Text(
                    'Normal (Baseline): ${metrics.baselineC != null ? '${metrics.baselineC!.toStringAsFixed(1)} \u00B0C' : 'N/A'}',
                    style: pw.TextStyle(
                      fontSize: 7.3,
                      fontWeight: pw.FontWeight.bold,
                      color: _dark,
                    ),
                  ),
                  pw.Text(
                    'Max: ${metrics.peakC != null ? '${metrics.peakC!.toStringAsFixed(1)} \u00B0C' : 'N/A'}',
                    style: pw.TextStyle(
                      fontSize: 7.3,
                      fontWeight: pw.FontWeight.bold,
                      color: isDeltaElevated ? _errorFg : _dark,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 10),
      ],

      // 4 Key Inspection Telemetry KPIs
      pw.Row(
        children: [
          pw.Expanded(
            child: _buildKpiBox(
              label: 'PEAK TEMPERATURE',
              value: metrics.peakC != null
                  ? '${metrics.peakC!.toStringAsFixed(1)} \u00B0C'
                  : 'N/A',
              sublabel: isDeltaElevated ? 'Above threshold' : 'Within normal',
              accentColor: isDeltaElevated ? _errorFg : _dark,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: _buildKpiBox(
              label: 'NORMAL BASELINE',
              value: metrics.baselineC != null
                  ? '${metrics.baselineC!.toStringAsFixed(1)} \u00B0C'
                  : 'N/A',
              sublabel: 'Reference panel temp',
              accentColor: _dark,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: _buildKpiBox(
              label: 'MAX THERMAL DELTA',
              value: metrics.maxDeltaC != null
                  ? '${metrics.maxDeltaC! >= 0 ? '+' : ''}${metrics.maxDeltaC!.toStringAsFixed(1)} \u00B0C'
                  : 'N/A',
              sublabel: 'Limit: +${threshold.toStringAsFixed(1)} \u00B0C',
              accentColor: isDeltaElevated ? _errorFg : _successFg,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: _buildKpiBox(
              label: 'ELECTRICAL OUTPUT',
              value: metrics.electrical.powerW != null
                  ? '${metrics.electrical.powerW!.toStringAsFixed(2)} W'
                  : 'N/A',
              sublabel: _formatElectricalSublabel(metrics.electrical),
              accentColor: _primary,
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 12),

      // Per-Panel Radiometric & Electrical Breakdown Table
      pw.Text(
        'PER-PANEL RADIOMETRIC & ELECTRICAL TELEMETRY',
        style: pw.TextStyle(
          fontSize: 8.5,
          fontWeight: pw.FontWeight.bold,
          color: _primary,
          letterSpacing: 0.4,
        ),
      ),
      pw.SizedBox(height: 5),
      pw.TableHelper.fromTextArray(
        headerStyle: pw.TextStyle(
          fontSize: 7.6,
          fontWeight: pw.FontWeight.bold,
          color: _white,
        ),
        headerDecoration: pw.BoxDecoration(color: _primary),
        cellStyle: pw.TextStyle(fontSize: 7.8, color: _dark),
        oddRowDecoration: pw.BoxDecoration(color: _surface),
        border: pw.TableBorder.all(color: _border, width: 0.5),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4.5),
        headers: const [
          'Panel',
          'Frames',
          'Baseline',
          'Peak Temp',
          'Max dT',
          'Voltage',
          'Current',
          'Power',
        ],
        data: [
          for (final row in metrics.panelRows)
            [
              'Panel ${row.panelIndex}',
              '${row.frameCount}',
              row.baselineC != null
                  ? '${row.baselineC!.toStringAsFixed(1)} \u00B0C'
                  : 'N/A',
              row.peakC != null
                  ? '${row.peakC!.toStringAsFixed(1)} \u00B0C'
                  : 'N/A',
              row.maxDeltaC != null
                  ? '${row.maxDeltaC! >= 0 ? '+' : ''}${row.maxDeltaC!.toStringAsFixed(1)} \u00B0C'
                  : 'N/A',
              row.electrical.voltageV != null
                  ? '${row.electrical.voltageV!.toStringAsFixed(2)} V'
                  : 'N/A',
              _formatCurrent(row.electrical.currentA),
              row.electrical.powerW != null
                  ? '${row.electrical.powerW!.toStringAsFixed(2)} W'
                  : 'N/A',
            ],
        ],
      ),
      pw.SizedBox(height: 12),

      // Confirmed Hotspots & Post-Cleaning Verification Section
      pw.Text(
        'HOTSPOT DIAGNOSTICS & POST-CLEANING VERIFICATION',
        style: pw.TextStyle(
          fontSize: 8.5,
          fontWeight: pw.FontWeight.bold,
          color: _primary,
          letterSpacing: 0.4,
        ),
      ),
      pw.SizedBox(height: 5),
    ];

    final summaries = entry.bundle.hotspotSummaries;
    final anomalies = entry.bundle.confirmedAnomalies;

    if (summaries.isNotEmpty) {
      widgets.add(
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(
            fontSize: 7.4,
            fontWeight: pw.FontWeight.bold,
            color: _white,
          ),
          headerDecoration: pw.BoxDecoration(color: _dark),
          cellStyle: pw.TextStyle(fontSize: 7.5, color: _dark),
          oddRowDecoration: pw.BoxDecoration(color: _surface),
          border: pw.TableBorder.all(color: _border, width: 0.5),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 5,
            vertical: 4,
          ),
          headers: const [
            '#',
            'Panel',
            'Position (X)',
            'Before',
            'After',
            'Change',
            'Wash / Duration',
            'Verdict',
          ],
          data: [
            for (var i = 0; i < summaries.length; i++)
              _buildHotspotSummaryRow(i + 1, summaries[i]),
          ],
        ),
      );
    } else if (anomalies.isNotEmpty) {
      widgets.add(
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(
            fontSize: 7.4,
            fontWeight: pw.FontWeight.bold,
            color: _white,
          ),
          headerDecoration: pw.BoxDecoration(color: _dark),
          cellStyle: pw.TextStyle(fontSize: 7.5, color: _dark),
          oddRowDecoration: pw.BoxDecoration(color: _surface),
          border: pw.TableBorder.all(color: _border, width: 0.5),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 5,
            vertical: 4,
          ),
          headers: const ['#', 'Panel', 'Position (X)', 'Attempts', 'Status'],
          data: [
            for (var i = 0; i < anomalies.length; i++)
              [
                'H${i + 1}',
                anomalies[i].panelIndex != null
                    ? 'P${anomalies[i].panelIndex}'
                    : '-',
                '${anomalies[i].xPositionCm.toStringAsFixed(1)} cm',
                '${anomalies[i].actuatedAttemptsCount}',
                _formatOutcomeLabel(anomalies[i].status),
              ],
          ],
        ),
      );
    } else {
      widgets.add(
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: pw.BoxDecoration(
            color: _successBg,
            borderRadius: pw.BorderRadius.circular(6),
            border: pw.Border.all(color: _successFg, width: 0.6),
          ),
          child: pw.Text(
            'RADIOMETRIC COMPLIANCE: No confirmed thermal hotspots above the +${threshold.toStringAsFixed(1)} \u00B0C threshold were detected during this inspection.',
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: _successFg,
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  static List<String> _buildHotspotSummaryRow(
    int index,
    HotspotVerificationSummary s,
  ) {
    final posStr = s.anomaly.localXPositionCm != null
        ? '${s.anomaly.xPositionCm.toStringAsFixed(1)} cm (L: ${s.anomaly.localXPositionCm!.toStringAsFixed(1)})'
        : '${s.anomaly.xPositionCm.toStringAsFixed(1)} cm';
    final beforeStr = s.beforeTempC > 0
        ? '${s.beforeTempC.toStringAsFixed(1)} \u00B0C'
        : 'N/A';
    final afterStr = s.afterTempC != null
        ? '${s.afterTempC!.toStringAsFixed(1)} \u00B0C'
        : '-';
    final deltaStr = s.deltaChangeC != null
        ? '${s.deltaChangeC! >= 0 ? '+' : ''}${s.deltaChangeC!.toStringAsFixed(1)} \u00B0C'
        : '-';
    final washStr = s.cleaning != null
        ? '#${s.cleaning!.attemptNumber ?? 1} / ${s.cleaning!.durationSeconds != null ? '${s.cleaning!.durationSeconds!.toStringAsFixed(1)} s' : 'N/A'}'
        : 'None';

    return [
      'H$index',
      s.anomaly.panelIndex != null ? 'P${s.anomaly.panelIndex}' : '-',
      posStr,
      beforeStr,
      afterStr,
      deltaStr,
      washStr,
      _formatOutcomeLabel(s.outcome),
    ];
  }

  static String _formatOutcomeLabel(String raw) {
    switch (raw.toLowerCase()) {
      case 'resolved':
      case 'verified_resolved':
        return 'Resolved';
      case 'resolved_later':
        return 'Cleared in Later Scan';
      case 'unresolved':
      case 'verified_unresolved':
        return 'Unresolved';
      case 'pending_verification':
      case 'pending':
        return 'Pending Check';
      case 'unwashed':
        return 'Not Washed';
      case 'open':
        return 'Open';
      default:
        return raw;
    }
  }

  static String _formatCurrent(double? currentA) {
    if (currentA == null) return 'N/A';
    if (currentA.abs() < 1.0) {
      return '${(currentA * 1000).toStringAsFixed(1)} mA';
    }
    return '${currentA.toStringAsFixed(2)} A';
  }

  static String _formatElectricalSublabel(ElectricalSummary elec) {
    if (elec.voltageV == null && elec.currentA == null && elec.powerW == null) {
      return 'No INA228 data';
    }
    final v = elec.voltageV != null
        ? '${elec.voltageV!.toStringAsFixed(2)} V'
        : 'N/A';
    final a = _formatCurrent(elec.currentA);
    return '$v | $a';
  }

  static pw.Widget _buildKpiBox({
    required String label,
    required String value,
    required String sublabel,
    required PdfColor accentColor,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: pw.BoxDecoration(
        color: _white,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: _border, width: 0.7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 6.5,
              fontWeight: pw.FontWeight.bold,
              color: _muted,
              letterSpacing: 0.3,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: accentColor,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            sublabel,
            style: pw.TextStyle(fontSize: 6.8, color: _muted),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPillBadge({
    required String label,
    required String tone,
  }) {
    final PdfColor bg;
    final PdfColor fg;
    switch (tone) {
      case 'success':
        bg = _successBg;
        fg = _successFg;
        break;
      case 'warning':
        bg = _warningBg;
        fg = _warningFg;
        break;
      case 'error':
        bg = _errorBg;
        fg = _errorFg;
        break;
      default:
        bg = _primarySoft;
        fg = _primary;
    }

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: fg, width: 0.6),
      ),
      child: pw.Text(
        label,
        style: pw.TextStyle(
          fontSize: 7.2,
          fontWeight: pw.FontWeight.bold,
          color: fg,
        ),
      ),
    );
  }
}
