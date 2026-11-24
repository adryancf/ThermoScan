/// Unified 24-hour English date & time formatting across ThermoScan.
class AppDateFormatter {
  AppDateFormatter._();

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Returns a compact relative string: "just now", "5m ago", "2h ago", "3d ago".
  static String formatRelativeTime(String? iso) {
    if (iso == null || iso.isEmpty) return 'recently';
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return 'recently';
    final diff = DateTime.now().toUtc().difference(parsed.toUtc());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  /// Returns "Today, 14:30" if same day, otherwise "Nov 24, 14:30".
  static String formatDateTimeShort(String? iso, {String fallback = 'Recent'}) {
    if (iso == null || iso.isEmpty) return fallback;
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    return formatDateTime(parsed, includeYear: false);
  }

  /// Returns "Today, 14:30" or "Nov 24, 14:30" (or "Nov 24, 2026 · 14:30" if [includeYear] is true).
  static String formatDateTime(
    DateTime? dt, {
    bool includeYear = false,
    String fallback = 'Recent',
  }) {
    if (dt == null) return fallback;
    final local = dt.toLocal();
    final now = DateTime.now();
    final isToday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;

    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final timeStr = '$hh:$mm';

    if (isToday) {
      return 'Today, $timeStr';
    }
    final month = _months[local.month - 1];
    if (includeYear) {
      return '$month ${local.day}, ${local.year} · $timeStr';
    }
    return '$month ${local.day}, $timeStr';
  }
}
