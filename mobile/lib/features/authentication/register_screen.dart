import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_failure.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/app_inputs.dart';
import '../../core/widgets/app_toast.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/app_providers.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _institutionCtrl = TextEditingController();
  final _specialtyOrGradeCtrl = TextEditingController();

  UserRole _selectedRole = UserRole.teacher;
  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _institutionCtrl.dispose();
    _specialtyOrGradeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await ref.read(authControllerProvider.notifier).register(
            email: _emailCtrl.text,
            password: _passwordCtrl.text,
            fullName: _nameCtrl.text,
            role: _selectedRole,
            institutionName: _institutionCtrl.text,
            subjectSpecialty:
                _selectedRole == UserRole.teacher ? _specialtyOrGradeCtrl.text : null,
            gradeLevel: _selectedRole == UserRole.student ? _specialtyOrGradeCtrl.text : null,
          );
      if (!mounted) return;
      AppToast.show(context, message: 'Akun berhasil dibuat.', variant: ToastVariant.success);
    } on AppFailure catch (err) {
      if (!mounted) return;
      AppToast.show(context, message: err.message, variant: ToastVariant.error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daftar Akun Baru'),
        leading: IconButton(
          onPressed: () => context.go('/login'),
          icon: const Icon(LucideIcons.arrowLeft),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pilih Peran Anda', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _RoleSelectorCard(
                        label: 'Pengajar',
                        subtitle: 'Buat materi & kelola kelas',
                        icon: LucideIcons.presentation,
                        selected: _selectedRole == UserRole.teacher,
                        onTap: () => setState(() => _selectedRole = UserRole.teacher),
                        accent: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _RoleSelectorCard(
                        label: 'Siswa',
                        subtitle: 'Ikuti kelas & kerjakan kuis',
                        icon: LucideIcons.graduationCap,
                        selected: _selectedRole == UserRole.student,
                        onTap: () => setState(() => _selectedRole = UserRole.student),
                        accent: scheme.secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                InputField(
                  controller: _nameCtrl,
                  label: 'Nama Lengkap',
                  hint: 'Budi Santoso',
                  prefixIcon: LucideIcons.user,
                  validator: (v) =>
                      (v == null || v.trim().length < 2) ? 'Nama minimal 2 karakter.' : null,
                ),
                const SizedBox(height: 14),
                InputField(
                  controller: _emailCtrl,
                  label: 'Email',
                  hint: 'nama@example.com',
                  prefixIcon: LucideIcons.mail,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) =>
                      (v == null || !v.contains('@')) ? 'Masukkan email yang valid.' : null,
                ),
                const SizedBox(height: 14),
                InputField(
                  controller: _passwordCtrl,
                  label: 'Kata Sandi',
                  hint: 'Min. 8 karakter (huruf besar, kecil, angka)',
                  prefixIcon: LucideIcons.lock,
                  obscureText: _obscure,
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure ? LucideIcons.eye : LucideIcons.eyeOff, size: 18),
                  ),
                  validator: (v) {
                    if (v == null || v.length < 8) return 'Kata sandi minimal 8 karakter.';
                    if (!RegExp(r'[A-Z]').hasMatch(v) ||
                        !RegExp(r'[a-z]').hasMatch(v) ||
                        !RegExp(r'[0-9]').hasMatch(v)) {
                      return 'Gunakan kombinasi huruf besar, huruf kecil, dan angka.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                InputField(
                  controller: _institutionCtrl,
                  label: 'Institusi / Sekolah (Opsional)',
                  hint: 'SMA Negeri 1 Contoh',
                  prefixIcon: LucideIcons.building2,
                ),
                const SizedBox(height: 14),
                InputField(
                  controller: _specialtyOrGradeCtrl,
                  label: _selectedRole == UserRole.teacher
                      ? 'Mata Pelajaran Utama (Opsional)'
                      : 'Tingkat / Kelas (Opsional)',
                  hint: _selectedRole == UserRole.teacher ? 'Biologi' : 'Kelas XI IPA',
                  prefixIcon: LucideIcons.bookMarked,
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Buat Akun',
                  icon: LucideIcons.userPlus,
                  isLoading: _submitting,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleSelectorCard extends StatelessWidget {
  const _RoleSelectorCard({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.accent,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.1) : Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent : scheme.outline,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: selected ? accent : scheme.onSurface, size: 22),
            const SizedBox(height: 10),
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
