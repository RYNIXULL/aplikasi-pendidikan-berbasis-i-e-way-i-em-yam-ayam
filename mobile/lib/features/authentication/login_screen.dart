import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_failure.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/app_inputs.dart';
import '../../core/widgets/app_toast.dart';
import '../../shared/providers/app_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await ref.read(authControllerProvider.notifier).login(
            email: _emailCtrl.text,
            password: _passwordCtrl.text,
          );
      if (!mounted) return;
      AppToast.show(context, message: 'Berhasil masuk ke akun Anda.', variant: ToastVariant.success);
    } on AppFailure catch (err) {
      if (!mounted) return;
      AppToast.show(context, message: err.message, variant: ToastVariant.error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showServerConfigSheet() async {
    final currentUrl = ref.read(apiBaseUrlProvider);
    final urlCtrl = TextEditingController(text: currentUrl);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Konfigurasi Server API', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Ubah alamat server jika IP Wi-Fi laptop berubah atau memakai server hosting.',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            InputField(
              controller: urlCtrl,
              label: 'Base URL API',
              hint: 'http://192.168.1.10:3000/api/v1',
              prefixIcon: LucideIcons.server,
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'Tes Koneksi',
                    icon: LucideIcons.wifi,
                    onPressed: () async {
                      final testBase = urlCtrl.text.trim().replaceAll(RegExp(r'/+$'), '');
                      try {
                        final dio = Dio(
                          BaseOptions(
                            connectTimeout: const Duration(seconds: 5),
                            receiveTimeout: const Duration(seconds: 5),
                          ),
                        );
                        await dio.get<Map<String, dynamic>>('$testBase/health');
                        if (ctx.mounted) {
                          AppToast.show(
                            ctx,
                            message: 'Koneksi ke server berhasil.',
                            variant: ToastVariant.success,
                          );
                        }
                      } catch (_) {
                        if (ctx.mounted) {
                          AppToast.show(
                            ctx,
                            message: 'Server tidak terjangkau di $testBase',
                            variant: ToastVariant.error,
                          );
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PrimaryButton(
                    label: 'Simpan',
                    icon: LucideIcons.check,
                    onPressed: () => Navigator.of(ctx).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (saved == true && mounted) {
      final cleaned = urlCtrl.text.trim().replaceAll(RegExp(r'/+$'), '');
      if (cleaned.startsWith('http://') || cleaned.startsWith('https://')) {
        ref.read(apiBaseUrlProvider.notifier).state = cleaned;
        AppToast.show(context, message: 'Server API diatur ke $cleaned', variant: ToastVariant.success);
      } else {
        AppToast.show(
          context,
          message: 'URL harus diawali http:// atau https://',
          variant: ToastVariant.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: _showServerConfigSheet,
                    icon: const Icon(LucideIcons.server, size: 20),
                    tooltip: 'Pengaturan Server API',
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(LucideIcons.bookOpen, color: scheme.primary, size: 28),
                ),
                const SizedBox(height: 20),
                Text('Masuk ke EduForge AI', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 6),
                Text(
                  'Kelola materi ajar AI atau lanjutkan pembelajaran kelas Anda.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 28),
                InputField(
                  controller: _emailCtrl,
                  label: 'Email',
                  hint: 'nama@example.com',
                  prefixIcon: LucideIcons.mail,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty || !v.contains('@')) {
                      return 'Masukkan alamat email yang valid.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                InputField(
                  controller: _passwordCtrl,
                  label: 'Kata Sandi',
                  hint: 'Masukkan kata sandi Anda',
                  prefixIcon: LucideIcons.lock,
                  obscureText: _obscure,
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure ? LucideIcons.eye : LucideIcons.eyeOff, size: 18),
                  ),
                  validator: (v) {
                    if (v == null || v.length < 8) {
                      return 'Kata sandi minimal 8 karakter.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Masuk',
                  icon: LucideIcons.logIn,
                  isLoading: _submitting,
                  onPressed: _submit,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Belum punya akun?', style: Theme.of(context).textTheme.bodyMedium),
                    TextButton(
                      onPressed: () => context.go('/register'),
                      child: const Text('Daftar Sekarang'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton.icon(
                    onPressed: _showServerConfigSheet,
                    icon: const Icon(LucideIcons.server, size: 14),
                    label: Text(
                      'Server: ${ref.watch(apiBaseUrlProvider)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
