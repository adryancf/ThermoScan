import 'package:flutter/services.dart';

/// Formatter that automatically inserts ':' every 2 hexadecimal characters
/// and forces all characters to uppercase (e.g. AA:BB:CC:DD:EE:FF).
class MacAddressInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Only keep hexadecimal characters
    final cleanHex = newValue.text.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
    final truncated = cleanHex.length > 12 ? cleanHex.substring(0, 12) : cleanHex;

    final buffer = StringBuffer();
    for (int i = 0; i < truncated.length; i++) {
      if (i > 0 && i % 2 == 0) {
        buffer.write(':');
      }
      buffer.write(truncated[i]);
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
