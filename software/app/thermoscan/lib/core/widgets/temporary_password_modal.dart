import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';

Future<void> showTemporaryPasswordModal({
  required BuildContext context,
  String title = 'Temporary Password',
  required String userName,
  required String userEmail,
  required String temporaryPassword,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _TemporaryPasswordDialog(
      title: title,
      userName: userName,
      userEmail: userEmail,
      temporaryPassword: temporaryPassword,
    ),
  );
}

class _TemporaryPasswordDialog extends StatefulWidget {
  const _TemporaryPasswordDialog({
    required this.title,
    required this.userName,
    required this.userEmail,
    required this.temporaryPassword,
  });

  final String title;
  final String userName;
  final String userEmail;
  final String temporaryPassword;

  @override
  State<_TemporaryPasswordDialog> createState() =>
      _TemporaryPasswordDialogState();
}

class _TemporaryPasswordDialogState extends State<_TemporaryPasswordDialog> {
  bool _copied = false;

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: widget.temporaryPassword));
    if (!mounted) return;
    setState(() {
      _copied = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primarySoft.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.vpn_key_outlined,
                color: AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: AppTypography.h3,
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.userName} • ${widget.userEmail}',
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: AppTypography.caption,
            ),
            const SizedBox(height: 16),
            // Monospace password box with integrated Copy button (prototype_1 style)
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: SelectableText(
                      widget.temporaryPassword,
                      maxLines: 1,
                      style: GoogleFonts.robotoMono(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  width: 48,
                  child: OutlinedButton(
                    onPressed: _copyToClipboard,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: _copied
                          ? AppColors.successBackground
                          : AppColors.surface,
                      side: BorderSide(
                        color:
                            _copied ? AppColors.successBorder : AppColors.border,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Icon(
                      _copied ? Icons.check : Icons.content_copy_outlined,
                      size: 20,
                      color: _copied ? AppColors.success : AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _copied
                  ? 'Copied to clipboard'
                  : 'Shown once • Must be changed on first sign-in',
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(
                color: _copied ? AppColors.success : AppColors.textSecondary,
                fontWeight: _copied ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: 'Done',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
