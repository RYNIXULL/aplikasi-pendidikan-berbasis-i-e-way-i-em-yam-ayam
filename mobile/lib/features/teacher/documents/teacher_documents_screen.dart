import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_cards.dart';
import '../../../core/widgets/app_inputs.dart';
import '../../../core/widgets/app_states.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../shared/models/models.dart';
import '../../../shared/providers/app_providers.dart';

final teacherDocumentsProvider = FutureProvider.autoDispose<List<DocumentModel>>((ref) async {
  try {
    final res = await ref.read(apiClientProvider).dio.get<Map<String, dynamic>>(ApiPaths.documents);
    final raw = (res.data?['data'] as List?) ?? const [];
    return raw
        .whereType<Map>()
        .map((e) => DocumentModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  } on DioException catch (e) {
    throw AppFailure.fromDioError(e);
  }
});

class TeacherDocumentsScreen extends ConsumerStatefulWidget {
  const TeacherDocumentsScreen({super.key});

  @override
  ConsumerState<TeacherDocumentsScreen> createState() => _TeacherDocumentsScreenState();
}

class _TeacherDocumentsScreenState extends ConsumerState<TeacherDocumentsScreen> {
  final _searchCtrl = TextEditingController();
  bool _uploading = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUpload() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: AppConfig.allowedUploadExtensions,
      withData: false,
    );
    if (picked == null || picked.files.isEmpty || picked.files.first.path == null) return;

    final file = picked.files.first;
    if (file.size > AppConfig.maxUploadBytes) {
      if (!mounted) return;
      AppToast.show(context, message: 'Ukuran file melebihi batas 25 MB.', variant: ToastVariant.error);
      return;
    }

    if (!mounted) return;
    final titleCtrl = TextEditingController(text: file.name.replaceAll(RegExp(r'\.[^.]+$'), ''));
    final subjectCtrl = TextEditingController(text: 'Biologi');
    final topicCtrl = TextEditingController();

    final proceed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Detail Dokumen Materi', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 14),
            InputField(controller: titleCtrl, label: 'Judul Materi', prefixIcon: LucideIcons.fileText),
            const SizedBox(height: 12),
            InputField(controller: subjectCtrl, label: 'Mata Pelajaran', prefixIcon: LucideIcons.bookOpen),
            const SizedBox(height: 12),
            InputField(controller: topicCtrl, label: 'Topik (Opsional)', prefixIcon: LucideIcons.tag),
            const SizedBox(height: 18),
            PrimaryButton(
              label: 'Unggah dan Analisis',
              icon: LucideIcons.upload,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      ),
    );

    if (proceed != true) return;

    setState(() => _uploading = true);
    try {
      final formData = FormData.fromMap({
        'title': titleCtrl.text.trim(),
        'subject': subjectCtrl.text.trim(),
        if (topicCtrl.text.trim().isNotEmpty) 'topic': topicCtrl.text.trim(),
        'file': await MultipartFile.fromFile(file.path!, filename: file.name),
      });
      await ref.read(apiClientProvider).dio.post<Map<String, dynamic>>(
            ApiPaths.documents,
            data: formData,
          );
      ref.invalidate(teacherDocumentsProvider);
      if (!mounted) return;
      AppToast.show(
        context,
        message: 'Dokumen berhasil diunggah dan sedang diproses.',
        variant: ToastVariant.success,
      );
    } on DioException catch (e) {
      if (!mounted) return;
      AppToast.show(context, message: AppFailure.fromDioError(e).message, variant: ToastVariant.error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteDoc(DocumentModel doc) async {
    final ok = await ConfirmationDialog.show(
      context,
      title: 'Hapus Dokumen',
      message: 'Dokumen "${doc.title}" akan dihapus dari daftar materi Anda.',
      confirmLabel: 'Hapus',
      isDestructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(apiClientProvider).dio.delete<void>('${ApiPaths.documents}/${doc.id}');
      ref.invalidate(teacherDocumentsProvider);
      if (!mounted) return;
      AppToast.show(context, message: 'Dokumen dihapus.', variant: ToastVariant.success);
    } on DioException catch (e) {
      if (!mounted) return;
      AppToast.show(context, message: AppFailure.fromDioError(e).message, variant: ToastVariant.error);
    }
  }

  Future<void> _showAnalysisSheet(DocumentModel doc) async {
    try {
      final res = await ref
          .read(apiClientProvider)
          .dio
          .get<Map<String, dynamic>>('${ApiPaths.documents}/${doc.id}/analysis');
      final analysis = (res.data?['data'] as Map<String, dynamic>?) ?? {};
      if (!mounted) return;

      final concepts = (analysis['keyConcepts'] as List?) ?? const [];
      final objectives = (analysis['learningObjectives'] as List?) ?? const [];

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          builder: (_, scrollCtrl) => ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(20),
            children: [
              Text('Analisis Materi AI', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text('${analysis['mainTopic'] ?? doc.title}',
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 16),
              Text('Tujuan Pembelajaran', style: Theme.of(ctx).textTheme.labelLarge),
              const SizedBox(height: 6),
              ...objectives.map((o) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(LucideIcons.check, size: 16),
                    title: Text(o.toString()),
                  )),
              const SizedBox(height: 12),
              Text('Konsep Penting', style: Theme.of(ctx).textTheme.labelLarge),
              const SizedBox(height: 6),
              ...concepts.whereType<Map>().map((c) => Card(
                    child: ListTile(
                      title: Text((c['name'] ?? '').toString()),
                      subtitle: Text((c['description'] ?? '').toString()),
                      trailing: SubjectBadge(
                        label: 'Hal. ${(c['source_pages'] as List?)?.join(", ") ?? "-"}',
                      ),
                    ),
                  )),
            ],
          ),
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      AppToast.show(context, message: AppFailure.fromDioError(e).message, variant: ToastVariant.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncDocs = ref.watch(teacherDocumentsProvider);
    final query = _searchCtrl.text.trim().toLowerCase();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Materi Saya'),
        actions: [
          IconButton(
            onPressed: _uploading ? null : _pickAndUpload,
            icon: const Icon(LucideIcons.filePlus2),
            tooltip: 'Unggah Dokumen',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SearchField(
              controller: _searchCtrl,
              hint: 'Cari judul atau mata pelajaran...',
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_uploading) const LinearProgressIndicator(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(teacherDocumentsProvider),
              child: asyncDocs.when(
                loading: () => const LoadingState(message: 'Memuat daftar dokumen...'),
                error: (err, _) => ErrorState(
                  message: err is AppFailure ? err.message : err.toString(),
                  onRetry: () => ref.invalidate(teacherDocumentsProvider),
                ),
                data: (docs) {
                  final filtered = query.isEmpty
                      ? docs
                      : docs
                          .where((d) =>
                              d.title.toLowerCase().contains(query) ||
                              d.subject.toLowerCase().contains(query))
                          .toList();
                  if (filtered.isEmpty) {
                    return EmptyState(
                      icon: LucideIcons.cloudUpload,
                      title: 'Belum Ada Dokumen Materi',
                      description: 'Unggah file PDF, DOCX, atau PPTX untuk dianalisis oleh AI.',
                      actionLabel: 'Unggah Dokumen',
                      onAction: _pickAndUpload,
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    itemCount: filtered.length,
                    itemBuilder: (_, idx) {
                      final doc = filtered[idx];
                      return DocumentCard(
                        title: doc.title,
                        subject: doc.subject,
                        format: doc.fileFormat,
                        status: doc.status,
                        progress: doc.processingProgress,
                        pageCount: doc.pageCount,
                        onTap: () => _showAnalysisSheet(doc),
                        onDelete: () => _deleteDoc(doc),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
