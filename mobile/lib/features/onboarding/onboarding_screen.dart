import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  static const _pages = [
    (
      icon: LucideIcons.fileText,
      title: 'Ubah Materi Ajar Jadi Konten Edukatif',
      description:
          'Unggah dokumen PDF, DOCX, atau PPTX. Sistem AI menganalisis struktur bab dan menghasilkan rangkuman, kuis, presentasi, hingga game edukatif.',
    ),
    (
      icon: LucideIcons.shieldCheck,
      title: 'Kendali Penuh di Tangan Pengajar',
      description:
          'Setiap konten AI mengacu pada halaman sumber, dapat ditinjau, diedit, disimpan versinya, dan hanya terbit ke kelas setelah disetujui pengajar.',
    ),
    (
      icon: LucideIcons.graduationCap,
      title: 'Belajar Interaktif untuk Siswa',
      description:
          'Gabung kelas dengan kode unik, pelajari rangkuman dan flashcards meski jaringan tidak stabil, ikuti kuis, dan mainkan game edukatif.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Lewati'),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, idx) {
                    final page = _pages[idx];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: Icon(page.icon, size: 46, color: scheme.primary),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          page.description,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (idx) {
                  final active = idx == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active ? scheme.primary : scheme.outline,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: _index == _pages.length - 1 ? 'Mulai Sekarang' : 'Lanjut',
                icon: LucideIcons.arrowRight,
                onPressed: () {
                  if (_index < _pages.length - 1) {
                    _controller.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  } else {
                    context.go('/login');
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
