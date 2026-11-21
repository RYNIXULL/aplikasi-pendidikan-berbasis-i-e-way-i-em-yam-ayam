import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
import '../../../shared/providers/app_providers.dart';
import '../../teacher/classrooms/teacher_classrooms_screen.dart';

class StudentClassroomsScreen extends ConsumerStatefulWidget {
  const StudentClassroomsScreen({super.key});

  @override
  ConsumerState<StudentClassroomsScreen> createState() => _StudentClassroomsScreenState();
}

class _StudentClassroomsScreenState extends ConsumerState<StudentClassroomsScreen> {
  Future<void> _showJoinDialog() async {
    final codeCtrl = TextEditingController();
    final join = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Gabung ke Kelas', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Masukkan kode kelas 8 karakter yang dibagikan oleh pengajar Anda.',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            InputField(
              controller: codeCtrl,
              label: 'Kode Kelas',
              hint: 'Contoh: BIO7X9K2',
              prefixIcon: LucideIcons.keyRound,
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: 'Gabung Kelas',
              icon: LucideIcons.arrowRight,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      ),
    );

    if (join != true || codeCtrl.text.trim().length < 6) return;

    try {
      await ref.read(apiClientProvider).dio.post<Map<String, dynamic>>(
        ApiPaths.joinClassroom,
        data: {'joinCode': codeCtrl.text.trim().toUpperCase()},
      );
      ref.invalidate(classroomsListProvider);
      if (!mounted) return;
      AppToast.show(context, message: 'Berhasil bergabung ke kelas.', variant: ToastVariant.success);
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
            onPressed: _showJoinDialog,
            icon: const Icon(LucideIcons.plus),
            tooltip: 'Gabung Kelas',
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
                title: 'Belum Bergabung di Kelas',
                description: 'Masukkan kode kelas dari pengajar untuk mengakses materi dan kuis.',
                actionLabel: 'Gabung Kelas',
                onAction: _showJoinDialog,
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: classes.length,
              itemBuilder: (_, idx) {
                final cls = classes[idx];
                return ContentCard(
                  title: cls.name,
                  contentTypeLabel: cls.subject,
                  statusLabel: '${cls.materialCount} materi',
                  statusColor: AppColors.secondary,
                  subtitle: cls.description ?? 'Ketuk untuk membuka materi kelas',
                  onTap: () => context.go('/student/learning'),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
