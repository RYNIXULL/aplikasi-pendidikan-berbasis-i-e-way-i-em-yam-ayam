import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_cards.dart';
import '../../../core/widgets/app_inputs.dart';
import '../../../core/widgets/app_states.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../shared/providers/app_providers.dart';
import '../documents/teacher_documents_screen.dart';

final teacherContentsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  try {
    final res = await ref.read(apiClientProvider).dio.get<Map<String, dynamic>>(ApiPaths.contents);
    final raw = (res.data?['data'] as List?) ?? const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  } on DioException catch (e) {
    throw AppFailure.fromDioError(e);
  }
});

class TeacherAiGeneratorScreen extends ConsumerStatefulWidget {
  const TeacherAiGeneratorScreen({super.key});

  @override
  ConsumerState<TeacherAiGeneratorScreen> createState() => _TeacherAiGeneratorScreenState();
}

class _TeacherAiGeneratorScreenState extends ConsumerState<TeacherAiGeneratorScreen> {
  String? _selectedDocId;
  String _contentType = 'SUMMARY';
  String _gameType = 'WORD_MATCHING';
  String _difficulty = 'medium';
  int _itemCount = 10;
  final _topicCtrl = TextEditingController();
  bool _generating = false;

  static const _contentTypes = [
    ('SUMMARY', 'Rangkuman', LucideIcons.fileText),
    ('QUIZ', 'Kuis & Ujian', LucideIcons.listChecks),
    ('PRESENTATION', 'Slide PPTX', LucideIcons.presentation),
    ('FLASHCARDS', 'Flashcards', LucideIcons.layers),
    ('MIND_MAP', 'Mind Map', LucideIcons.gitFork),
    ('WORKSHEET', 'Worksheet', LucideIcons.clipboardList),
    ('GAME', 'Game Edukatif', LucideIcons.gamepad2),
  ];

  static const _gameTypes = [
    ('QUIZ_BATTLE', 'Quiz Battle'),
    ('WORD_MATCHING', 'Word Matching'),
    ('TRUE_FALSE', 'True or False'),
    ('MEMORY_CARDS', 'Memory Cards'),
    ('CROSSWORD', 'Crossword'),
    ('WORD_PUZZLE', 'Word Puzzle'),
  ];

  @override
  void dispose() {
    _topicCtrl.dispose();
    super.dispose();
  }

  Future<void> _triggerGenerate() async {
    if (_selectedDocId == null) {
      AppToast.show(
        context,
        message: 'Pilih dokumen sumber berstatus READY terlebih dahulu.',
        variant: ToastVariant.warning,
      );
      return;
    }

    setState(() => _generating = true);
    try {
      await ref.read(apiClientProvider).dio.post<Map<String, dynamic>>(
        ApiPaths.aiGenerate,
        options: Options(headers: {'Idempotency-Key': const Uuid().v4()}),
        data: {
          'documentId': _selectedDocId,
          'contentType': _contentType,
          if (_contentType == 'GAME') 'gameType': _gameType,
          'config': {
            'difficulty': _difficulty,
            'questionCount': _itemCount,
            if (_topicCtrl.text.trim().isNotEmpty) 'topicFocus': _topicCtrl.text.trim(),
            'language': 'id',
          },
        },
      );
      ref.invalidate(teacherContentsProvider);
      if (!mounted) return;
      AppToast.show(
        context,
        message: 'Permintaan generasi AI masuk antrean. Periksa daftar draf Anda.',
        variant: ToastVariant.success,
      );
    } on DioException catch (e) {
      if (!mounted) return;
      AppToast.show(context, message: AppFailure.fromDioError(e).message, variant: ToastVariant.error);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncDocs = ref.watch(teacherDocumentsProvider);
    final asyncContents = ref.watch(teacherContentsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('AI Generator')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.cpu, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text('Konfigurasi Generasi Konten',
                          style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 14),
                  asyncDocs.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Gagal memuat dokumen: $e'),
                    data: (docs) {
                      final readyDocs =
                          docs.where((d) => d.status == 'READY' || d.status == 'ANALYZED').toList();
                      return DropdownButtonFormField<String>(
                        value: readyDocs.any((d) => d.id == _selectedDocId) ? _selectedDocId : null,
                        decoration: const InputDecoration(
                          labelText: 'Dokumen Sumber (READY)',
                          prefixIcon: Icon(LucideIcons.fileCheck, size: 18),
                        ),
                        items: readyDocs
                            .map((d) => DropdownMenuItem(value: d.id, child: Text(d.title)))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedDocId = v),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text('Format Konten', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _contentTypes.map((item) {
                      final selected = _contentType == item.$1;
                      return ChoiceChip(
                        avatar: Icon(item.$3, size: 15),
                        label: Text(item.$2),
                        selected: selected,
                        onSelected: (_) => setState(() => _contentType = item.$1),
                      );
                    }).toList(),
                  ),
                  if (_contentType == 'GAME') ...[
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: _gameType,
                      decoration: const InputDecoration(
                        labelText: 'Jenis Permainan Edukatif',
                        prefixIcon: Icon(LucideIcons.gamepad2, size: 18),
                      ),
                      items: _gameTypes
                          .map((g) => DropdownMenuItem(value: g.$1, child: Text(g.$2)))
                          .toList(),
                      onChanged: (v) => setState(() => _gameType = v ?? 'WORD_MATCHING'),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _difficulty,
                          decoration: const InputDecoration(labelText: 'Kesulitan'),
                          items: const [
                            DropdownMenuItem(value: 'easy', child: Text('Mudah')),
                            DropdownMenuItem(value: 'medium', child: Text('Sedang')),
                            DropdownMenuItem(value: 'hard', child: Text('Sulit')),
                          ],
                          onChanged: (v) => setState(() => _difficulty = v ?? 'medium'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _itemCount,
                          decoration: const InputDecoration(labelText: 'Jumlah Item'),
                          items: const [5, 10, 15, 20]
                              .map((n) => DropdownMenuItem(value: n, child: Text('$n item')))
                              .toList(),
                          onChanged: (v) => setState(() => _itemCount = v ?? 10),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  InputField(
                    controller: _topicCtrl,
                    label: 'Fokus Topik / Bab (Opsional)',
                    hint: 'Contoh: Organ Pencernaan',
                    prefixIcon: LucideIcons.target,
                  ),
                  const SizedBox(height: 18),
                  PrimaryButton(
                    label: 'Generate Konten AI',
                    icon: LucideIcons.cpu,
                    isLoading: _generating,
                    onPressed: _triggerGenerate,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text('Draf & Riwayat Generasi', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          asyncContents.when(
            loading: () => const LoadingState(message: 'Memuat konten...'),
            error: (err, _) => ErrorState(
              message: err is AppFailure ? err.message : err.toString(),
              onRetry: () => ref.invalidate(teacherContentsProvider),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const EmptyState(
                  icon: LucideIcons.layers,
                  title: 'Belum Ada Hasil Generasi',
                  description: 'Konten yang dihasilkan AI akan tampil di sini untuk Anda tinjau.',
                );
              }
              return Column(
                children: items.map((c) {
                  final status = (c['status'] ?? 'DRAFT').toString();
                  final color = status == 'APPROVED' || status == 'PUBLISHED'
                      ? AppColors.success
                      : AppColors.warning;
                  return ContentCard(
                    title: (c['title'] ?? '').toString(),
                    contentTypeLabel: (c['contentType'] ?? '').toString(),
                    statusLabel: status,
                    statusColor: color,
                    subject: c['subject']?.toString(),
                    onTap: () => context.push('/teacher/content/${c['id']}'),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
