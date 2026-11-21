import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_cards.dart';
import '../../../core/widgets/app_states.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../shared/providers/app_providers.dart';
import '../classrooms/teacher_classrooms_screen.dart';

class TeacherAssessmentsScreen extends ConsumerStatefulWidget {
  const TeacherAssessmentsScreen({super.key});

  @override
  ConsumerState<TeacherAssessmentsScreen> createState() => _TeacherAssessmentsScreenState();
}

class _TeacherAssessmentsScreenState extends ConsumerState<TeacherAssessmentsScreen> {
  String? _selectedClassroomId;
  bool _loadingAssessments = false;
  String? _error;
  List<Map<String, dynamic>> _assessments = const [];

  Future<void> _fetchForClassroom(String classroomId) async {
    setState(() {
      _selectedClassroomId = classroomId;
      _loadingAssessments = true;
      _error = null;
    });
    try {
      final res = await ref
          .read(apiClientProvider)
          .dio
          .get<Map<String, dynamic>>('${ApiPaths.classrooms}/$classroomId/assessments');
      final raw = (res.data?['data'] as List?) ?? const [];
      _assessments = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } on DioException catch (e) {
      _error = AppFailure.fromDioError(e).message;
    } finally {
      if (mounted) setState(() => _loadingAssessments = false);
    }
  }

  Future<void> _publishAssessment(String id) async {
    try {
      await ref.read(apiClientProvider).dio.post<void>('${ApiPaths.assessments}/$id/publish');
      if (_selectedClassroomId != null) await _fetchForClassroom(_selectedClassroomId!);
      if (!mounted) return;
      AppToast.show(context, message: 'Evaluasi dipublikasikan ke kelas.', variant: ToastVariant.success);
    } on DioException catch (e) {
      if (!mounted) return;
      AppToast.show(context, message: AppFailure.fromDioError(e).message, variant: ToastVariant.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncClasses = ref.watch(classroomsListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Evaluasi & Ujian')),
      body: asyncClasses.when(
        loading: () => const LoadingState(message: 'Memuat kelas...'),
        error: (err, _) => ErrorState(
          message: err is AppFailure ? err.message : err.toString(),
          onRetry: () => ref.invalidate(classroomsListProvider),
        ),
        data: (classes) {
          if (classes.isEmpty) {
            return const EmptyState(
              icon: LucideIcons.clipboardList,
              title: 'Belum Ada Kelas',
              description: 'Buat kelas terlebih dahulu sebelum mengelola kuis dan ujian.',
            );
          }

          if (_selectedClassroomId == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _selectedClassroomId == null) {
                _fetchForClassroom(classes.first.id);
              }
            });
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: DropdownButtonFormField<String>(
                  value: classes.any((c) => c.id == _selectedClassroomId)
                      ? _selectedClassroomId
                      : classes.first.id,
                  decoration: const InputDecoration(
                    labelText: 'Pilih Kelas',
                    prefixIcon: Icon(LucideIcons.school, size: 18),
                  ),
                  items: classes
                      .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                      .toList(),
                  onChanged: (id) {
                    if (id != null) _fetchForClassroom(id);
                  },
                ),
              ),
              Expanded(
                child: _loadingAssessments
                    ? const LoadingState(message: 'Memuat evaluasi...')
                    : _error != null
                        ? ErrorState(
                            message: _error!,
                            onRetry: () {
                              if (_selectedClassroomId != null) {
                                _fetchForClassroom(_selectedClassroomId!);
                              }
                            },
                          )
                        : _assessments.isEmpty
                            ? const EmptyState(
                                icon: LucideIcons.fileCheck2,
                                title: 'Belum Ada Evaluasi',
                                description:
                                    'Buat kuis melalui AI Generator, setujui, lalu jadikan evaluasi kelas.',
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                                itemCount: _assessments.length,
                                itemBuilder: (_, idx) {
                                  final a = _assessments[idx];
                                  final status = (a['status'] ?? 'DRAFT').toString();
                                  final counts = (a['_count'] as Map<String, dynamic>?) ?? {};
                                  return ContentCard(
                                    title: (a['title'] ?? '').toString(),
                                    contentTypeLabel: (a['assessmentType'] ?? 'SELF_QUIZ').toString(),
                                    statusLabel: status,
                                    statusColor: status == 'PUBLISHED'
                                        ? AppColors.success
                                        : AppColors.warning,
                                    subtitle:
                                        '${counts['questions'] ?? 0} soal - ${counts['attempts'] ?? 0} pengerjaan',
                                    trailing: status == 'DRAFT'
                                        ? TextButton(
                                            onPressed: () =>
                                                _publishAssessment(a['id'].toString()),
                                            child: const Text('Terbitkan'),
                                          )
                                        : null,
                                  );
                                },
                              ),
              ),
            ],
          );
        },
      ),
    );
  }
}
