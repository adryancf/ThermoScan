import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';

/// Modal scanner to scan QR codes or Barcodes containing an ESP32 MAC address
class MacQrScannerModal extends StatefulWidget {
  const MacQrScannerModal({super.key});

  @override
  State<MacQrScannerModal> createState() => _MacQrScannerModalState();
}

class _MacQrScannerModalState extends State<MacQrScannerModal> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _scanned = false;

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue != null && rawValue.trim().isNotEmpty) {
        final extractedMac = _extractMac(rawValue.trim());
        if (extractedMac != null) {
          _scanned = true;
          Navigator.of(context).pop(extractedMac);
          return;
        }
      }
    }
  }

  /// Extracts standard MAC from QR/Barcode content if present
  String? _extractMac(String raw) {
    // 1. Check for standard separated MAC (e.g., AA:BB:CC:DD:EE:FF or AA-BB-CC-DD-EE-FF)
    final sepRegex = RegExp(r'([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})');
    final match = sepRegex.firstMatch(raw);
    if (match != null) {
      return match.group(0)!.replaceAll('-', ':').toUpperCase();
    }

    // 2. Check for continuous 12-hex string (e.g. AABBCCDDEEFF)
    final contRegex = RegExp(r'\b([0-9A-Fa-f]{12})\b');
    final contMatch = contRegex.firstMatch(raw);
    if (contMatch != null) {
      final hex = contMatch.group(1)!.toUpperCase();
      final buf = StringBuffer();
      for (int i = 0; i < 12; i++) {
        if (i > 0 && i % 2 == 0) buf.write(':');
        buf.write(hex[i]);
      }
      return buf.toString();
    }

    return null;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Scan Module MAC / QR Code',
          style: AppTypography.h3.copyWith(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on, color: Colors.white),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 48,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Point camera at the ESP32 MAC QR code or barcode on the hardware label.',
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
