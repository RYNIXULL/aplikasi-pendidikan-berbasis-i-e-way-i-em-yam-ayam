import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/app_cards.dart';
import '../../core/widgets/app_states.dart';
import '../../core/widgets/app_toast.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/app_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final themeMode = ref.watch(themeModeProvider);

    if (user == null) {
      return const LoadingState(message: 'Memuat profil...');
    }

    final isTeacher = user.role == UserRole.teacher;

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.14),
                    child: Icon(
                      isTeacher ? LucideIcons.presentation : LucideIcons.graduationCap,
                      size: 28,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.fullName, style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(user.email, style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 8),
                        SubjectBadge(
                          label: isTeacher ? 'Pengajar' : 'Siswa',
                          color: isTeacher ? AppColors.primary : AppColors.secondary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(LucideIcons.sunMoon),
                  title: const Text('Tema Aplikasi'),
                  subtitle: Text(
                    themeMode == ThemeMode.dark
                        ? 'Mode Gelap'
                        : themeMode == ThemeMode.light
                            ? 'Mode Terang'
                            : 'Ikuti Sistem',
                  ),
                  trailing: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.light, icon: Icon(LucideIcons.sun, size: 16)),
                      ButtonSegment(value: ThemeMode.dark, icon: Icon(LucideIcons.moon, size: 16)),
                    ],
                    selected: {
                      themeMode == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light,
                    },
                    onSelectionChanged: (s) {
                      ref.read(themeModeProvider.notifier).state = s.first;
                    },
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(LucideIcons.building2),
                  title: const Text('Institusi'),
                  subtitle: Text(user.institutionName ?? 'Belum diatur'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(LucideIcons.bookOpen),
                  title: Text(isTeacher ? 'Bidang Studi' : 'Tingkat Kelas'),
                  subtitle: Text(
                    (isTeacher ? user.subjectSpecialty : user.gradeLevel) ?? 'Belum diatur',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SecondaryButton(
            label: 'Keluar dari Akun',
            icon: LucideIcons.logOut,
            onPressed: () async {
              final confirmed = await ConfirmationDialog.show(
                context,
                title: 'Keluar dari Akun',
                message: 'Anda akan keluar dari sesi saat ini pada perangkat ini.',
                confirmLabel: 'Keluar',
                isDestructive: true,
              );
              if (!confirmed || !context.mounted) return;
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) {
                AppToast.show(context, message: 'Anda telah keluar.', variant: ToastVariant.info);
              }
            },
          ),
        ],
      ),
    );
  }
}
