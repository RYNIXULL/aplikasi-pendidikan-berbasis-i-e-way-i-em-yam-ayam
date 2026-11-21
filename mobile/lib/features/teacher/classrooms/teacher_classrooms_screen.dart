import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_cards.dart';
import '../../../core/widgets/app_inputs.dart';
import '../../../core/widgets/app_states.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../shared/models/models.dart';
import '../../../shared/providers/app_providers.dart';

final classroomsListProvider = FutureProvider.autoDispose<List<ClassroomModel>>((ref) async {
  try {
    final res = await ref.read(apiClientProvider).dio.get<Map<String, dynamic>>(ApiPaths.classrooms);
    final raw = (res.data?['data'] as List?) ?? const [];
    return raw
        .whereType<Map>()
        .map((e) => ClassroomModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  } on DioException catch (e) {
    throw AppFailure.fromDioError(e);
  }
});

class TeacherClassroomsScreen extends ConsumerStatefulWidget {
  const TeacherClassroomsScreen({super.key});

  @override
  ConsumerState<TeacherClassroomsScreen> createState() => _TeacherClassroomsScreenState();
}

class _TeacherClassroomsScreenState extends ConsumerState<TeacherClassroomsScreen> {
  Future<void> _showCreateClassroomSheet() async {
    final nameCtrl = TextEditingController();
    final subjectCtrl = TextEditingController();
    final gradeCtrl = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Buat Kelas Baru', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 14),
            InputField(
              controller: nameCtrl,
              label: 'Nama Kelas',
              hint: 'Biologi XI IPA 1',
              prefixIcon: LucideIcons.school,
            ),
            const SizedBox(height: 12),
            InputField(
              controller: subjectCtrl,
              label: 'Mata Pelajaran',
              hint: 'Biologi',
              prefixIcon: LucideIcons.bookOpen,
            ),
            const SizedBox(height: 12),
            InputField(
              controller: gradeCtrl,
              label: 'Tingkat / Kelas (Opsional)',
              hint: 'Kelas XI',
              prefixIcon: LucideIcons.graduationCap,
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: 'Buat Kelas',
              icon: LucideIcons.plus,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || nameCtrl.text.trim().isEmpty || subjectCtrl.text.trim().isEmpty) {
      return;
    }

    try {
      await ref.read(apiClientProvider).dio.post<Map<String, dynamic>>(
        ApiPaths.classrooms,
        data: {
          'name': nameCtrl.text.trim(),
          'subject': subjectCtrl.text.trim(),
          if (gradeCtrl.text.trim().isNotEmpty) 'gradeLevel': gradeCtrl.text.trim(),
        },
      );
      ref.invalidate(classroomsListProvider);
      if (!mounted) return;
      AppToast.show(context, message: 'Kelas berhasil dibuat.', variant: ToastVariant.success);
    } on DioException catch (e) {
      if (!mounted) return;
      AppToast.show(context, message: AppFailure.fromDioError(e).message, variant: ToastVariant.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncClasses = ref.watch(classroomsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelas Saya'),
        actions: [
          IconButton(
            onPressed: _showCreateClassroomSheet,
            icon: const Icon(LucideIcons.plus),
            tooltip: 'Buat Kelas',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(classroomsListProvider),
        child: asyncClasses.when(
          loading: () => const LoadingState(message: 'Memuat daftar kelas...'),
          error: (err, _) => ErrorState(
            message: err is AppFailure ? err.message : err.toString(),
            onRetry: () => ref.invalidate(classroomsListProvider),
          ),
          data: (classes) {
            if (classes.isEmpty) {
              return EmptyState(
                icon: LucideIcons.school,
                title: 'Belum Ada Kelas',
                description: 'Buat kelas digital untuk membagikan materi AI dan ujian ke siswa.',
                actionLabel: 'Buat Kelas Pertama',
                onAction: _showCreateClassroomSheet,
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: classes.length,
              itemBuilder: (_, idx) {
                final cls = classes[idx];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(cls.name, style: Theme.of(context).textTheme.titleMedium),
                            ),
                            SubjectBadge(
                              label: cls.status,
                              color: cls.status == 'ACTIVE' ? AppColors.success : AppColors.warning,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          children: [
                            SubjectBadge(label: cls.subject),
                            SubjectBadge(
                              label: '${cls.memberCount} siswa',
                              icon: LucideIcons.users,
                              color: AppColors.secondary,
                            ),
                            SubjectBadge(
                              label: '${cls.materialCount} materi',
                              icon: LucideIcons.layers,
                              color: AppColors.info,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(LucideIcons.keyRound, size: 15),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Kode: ${cls.joinCode}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: cls.joinCode));
                                AppToast.show(
                                  context,
                                  message: 'Kode kelas ${cls.joinCode} disalin.',
                                  variant: ToastVariant.success,
                                );
                              },
                              icon: const Icon(LucideIcons.copy, size: 18),
                              tooltip: 'Salin kode kelas',
                            ),
                            IconButton(
                              onPressed: () => context.push('/teacher/analytics/${cls.id}'),
                              icon: const Icon(LucideIcons.chartColumn, size: 18),
                              tooltip: 'Analitik kelas',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
