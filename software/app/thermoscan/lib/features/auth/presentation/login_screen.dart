import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermoscan/core/config/app_config.dart';
import 'package:thermoscan/core/network/api_client.dart';
import 'package:thermoscan/core/network/api_exception.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/theme/app_typography.dart';
import 'package:thermoscan/core/widgets/app_buttons.dart';
import 'package:thermoscan/core/widgets/app_text_field.dart';
import 'package:thermoscan/core/widgets/thermoscan_logo.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';

/// SCR-02: Login Screen
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    ref.read(authControllerProvider.notifier).clearInfoMessage();
    setState(() {
      _errorMessage = null;
    });

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await ref.read(authControllerProvider.notifier).login(
            email: _emailController.text,
            password: _passwordController.text,
          );
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _errorMessage = err.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to sign in. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final infoMessage = authState.infoMessage;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const ThermoScanBrandMark(iconSize: 28, fontSize: 22),
                            IconButton(
                              icon: const Icon(
                                Icons.settings_ethernet_outlined,
                                color: AppColors.textSecondary,
                                size: 24,
                              ),
                              tooltip: 'Server Connection Settings',
                              onPressed: () => _showServerSettingsDialog(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'Login',
                          style: AppTypography.h2,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Authenticate with your enterprise credentials',
                          style: AppTypography.bodySmall,
                        ),
                        const SizedBox(height: 24),
                        if (infoMessage != null && infoMessage.isNotEmpty) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: AppColors.successBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.successBorder,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_outline,
                                  color: AppColors.success,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    infoMessage,
                                    style: AppTypography.bodySmall.copyWith(
                                      color: AppColors.success,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (_errorMessage != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: AppColors.errorBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.errorBorder),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: AppColors.error,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: AppTypography.bodySmall.copyWith(
                                      color: AppColors.error,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AppTextField(
                                  label: 'Corporate Email',
                                  controller: _emailController,
                                  hintText: 'user@company.com',
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  prefixIcon: Icons.mail_outline,
                                  autofillHints: const [AutofillHints.email],
                                  validator: (value) {
                                    final trimmed = value?.trim() ?? '';
                                    if (trimmed.isEmpty) {
                                      return 'Email is required.';
                                    }
                                    if (!trimmed.contains('@')) {
                                      return 'Enter a valid email address.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                AppTextField(
                                  label: 'Password',
                                  controller: _passwordController,
                                  hintText: 'Enter your password',
                                  isPassword: true,
                                  textInputAction: TextInputAction.done,
                                  prefixIcon: Icons.lock_outline,
                                  autofillHints: const [AutofillHints.password],
                                  onFieldSubmitted: (_) => _handleLogin(),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Password is required.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 24),
                                PrimaryButton(
                                  label: 'Log In',
                                  icon: Icons.login,
                                  isLoading: _isSubmitting,
                                  onPressed: _handleLogin,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Center(
                        child: Text(
                          'Encrypted Telemetry Hub • IEC 62446-3 Compliant',
                          textAlign: TextAlign.center,
                          style: AppTypography.caption,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showServerSettingsDialog(BuildContext context) async {
    final currentUrl = ref.read(baseUrlProvider);
    final ctrl = TextEditingController(text: currentUrl);
    var testing = false;
    String? testResult;
    bool? testSuccess;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  const Icon(Icons.dns_outlined, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text('Server Host', style: AppTypography.h3),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Configure backend API address (e.g. Wi-Fi IP changes).',
                    style: AppTypography.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: 'API Base URL',
                    controller: ctrl,
                    hintText: 'http://10.0.2.2:8080/api/v1',
                  ),
                  if (testResult != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          testSuccess == true
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          size: 16,
                          color: testSuccess == true
                              ? AppColors.success
                              : AppColors.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            testResult!,
                            style: AppTypography.caption.copyWith(
                              color: testSuccess == true
                                  ? AppColors.success
                                  : AppColors.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    ctrl.text = AppConfig.defaultApiBaseUrl;
                    setDialogState(() {
                      testResult = null;
                      testSuccess = null;
                    });
                  },
                  child: const Text('Reset Default'),
                ),
                TextButton(
                  onPressed: testing
                      ? null
                      : () async {
                          setDialogState(() {
                            testing = true;
                            testResult = null;
                          });
                          try {
                            final testUrl = ctrl.text.trim();
                            final healthUrl = testUrl.replaceAll(
                              RegExp(r'/api/v1/?$'),
                              '/health',
                            );
                            final dio = Dio(
                              BaseOptions(
                                connectTimeout: const Duration(seconds: 4),
                              ),
                            );
                            final res = await dio.get<dynamic>(healthUrl);
                            setDialogState(() {
                              testing = false;
                              testSuccess = (res.statusCode == 200);
                              testResult = testSuccess!
                                  ? 'Connected successfully!'
                                  : 'Server replied with status ${res.statusCode}';
                            });
                          } catch (e) {
                            setDialogState(() {
                              testing = false;
                              testSuccess = false;
                              testResult = 'Connection failed. Check IP & Wi-Fi.';
                            });
                          }
                        },
                  child: testing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Test Connection'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final newUrl = ctrl.text.trim();
                    if (newUrl.isNotEmpty) {
                      await AppConfig.setBaseUrl(newUrl);
                      ref.read(baseUrlProvider.notifier).state = newUrl;
                    }
                    if (context.mounted) {
                      Navigator.of(dialogCtx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Server URL set to: $newUrl'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
