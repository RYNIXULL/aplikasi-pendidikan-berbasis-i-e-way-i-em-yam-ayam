import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_cards.dart';
import '../../../core/widgets/app_states.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../shared/models/models.dart';
import '../../../shared/providers/app_providers.dart';

class GamePlayResult {
  const GamePlayResult({
    required this.score,
    required this.maxScore,
    required this.accuracyPercentage,
    required this.durationSeconds,
    required this.streakMax,
  });

  final int score;
  final int maxScore;
  final double accuracyPercentage;
  final int durationSeconds;
  final int streakMax;
}

/// Template-Based Educational Game Host Screen.
/// Loads validated declarative JSON config from backend and mounts the
/// matching native Flutter game renderer (zero AI-generated executable code).
class GameEngineScreen extends ConsumerStatefulWidget {
  const GameEngineScreen({super.key, required this.materialId, this.initialConfig});

  final String materialId;
  final GameConfigModel? initialConfig;

  @override
  ConsumerState<GameEngineScreen> createState() => _GameEngineScreenState();
}

class _GameEngineScreenState extends ConsumerState<GameEngineScreen> {
  GameConfigModel? _config;
  bool _loading = true;
  String? _error;
  GamePlayResult? _completedResult;
  List<Map<String, dynamic>> _leaderboard = const [];

  @override
  void initState() {
    super.initState();
    if (widget.initialConfig != null) {
      _config = widget.initialConfig;
      _loading = false;
    } else {
      _fetchConfig();
    }
  }

  Future<void> _fetchConfig() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider).dio;
      final res = await api.get<Map<String, dynamic>>('${ApiPaths.games}/${widget.materialId}/config');
      final data = (res.data?['data'] as Map<String, dynamic>?) ?? {};
      final rawConfig = (data['config'] as Map<String, dynamic>?) ?? {};
      _config = GameConfigModel.fromJson(rawConfig, materialId: widget.materialId);
    } on DioException catch (e) {
      _error = AppFailure.fromDioError(e).message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onGameFinished(GamePlayResult result) async {
    setState(() => _completedResult = result);
    if (widget.materialId.isEmpty) return;

    try {
      final api = ref.read(apiClientProvider).dio;
      await api.post<void>(
        '${ApiPaths.games}/${widget.materialId}/sessions',
        data: {
          'score': result.score,
          'maxScore': result.maxScore,
          'accuracyPercentage': result.accuracyPercentage,
          'durationSeconds': max(1, result.durationSeconds),
          'streakMax': result.streakMax,
          'completed': true,
        },
      );
      final lb = await api.get<Map<String, dynamic>>(
        '${ApiPaths.games}/${widget.materialId}/leaderboard',
      );
      final rawLb = (lb.data?['data'] as List?) ?? const [];
      if (mounted) {
        setState(() {
          _leaderboard = rawLb.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, message: 'Skor selesai dicatat secara lokal.', variant: ToastVariant.info);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_config?.title ?? 'Permainan Edukatif')),
      body: _loading
          ? const LoadingState(message: 'Menyiapkan permainan...')
          : _error != null
              ? ErrorState(message: _error!, onRetry: _fetchConfig)
              : _completedResult != null
                  ? _GameResultView(
                      config: _config!,
                      result: _completedResult!,
                      leaderboard: _leaderboard,
                      onPlayAgain: () => setState(() => _completedResult = null),
                    )
                  : _buildRenderer(_config!),
    );
  }

  Widget _buildRenderer(GameConfigModel config) {
    switch (config.gameType) {
      case 'quiz_battle':
        return QuizBattleRenderer(config: config, onComplete: _onGameFinished);
      case 'word_matching':
        return WordMatchingRenderer(config: config, onComplete: _onGameFinished);
      case 'true_false':
        return TrueFalseRenderer(config: config, onComplete: _onGameFinished);
      case 'memory_cards':
        return MemoryCardRenderer(config: config, onComplete: _onGameFinished);
      case 'crossword':
        return CrosswordRenderer(config: config, onComplete: _onGameFinished);
      case 'word_puzzle':
        return WordPuzzleRenderer(config: config, onComplete: _onGameFinished);
      default:
        return ErrorState(message: 'Jenis permainan tidak dikenali: ${config.gameType}');
    }
  }
}

class _GameResultView extends StatelessWidget {
  const _GameResultView({
    required this.config,
    required this.result,
    required this.leaderboard,
    required this.onPlayAgain,
  });

  final GameConfigModel config;
  final GamePlayResult result;
  final List<Map<String, dynamic>> leaderboard;
  final VoidCallback onPlayAgain;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(LucideIcons.trophy, size: 52, color: AppColors.secondary),
                const SizedBox(height: 12),
                Text('Permainan Selesai', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  '${result.score} / ${result.maxScore}',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 34),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    SubjectBadge(
                      label: 'Akurasi ${result.accuracyPercentage.toStringAsFixed(0)}%',
                      color: AppColors.success,
                    ),
                    SubjectBadge(
                      label: '${result.durationSeconds} detik',
                      icon: LucideIcons.clock,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (leaderboard.isNotEmpty) ...[
          Text('Papan Peringkat Kelas', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...leaderboard.map((row) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    child: Text('#${row['rank']}'),
                  ),
                  title: Text((row['displayName'] ?? 'Siswa').toString()),
                  trailing: Text(
                    '${row['bestScore']} pts',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              )),
          const SizedBox(height: 16),
        ],
        PrimaryButton(label: 'Main Lagi', icon: LucideIcons.rotateCcw, onPressed: onPlayAgain),
      ],
    );
  }
}

// ============================================================================
// 1. QuizBattleRenderer
// ============================================================================
class QuizBattleRenderer extends StatefulWidget {
  const QuizBattleRenderer({super.key, required this.config, required this.onComplete});

  final GameConfigModel config;
  final ValueChanged<GamePlayResult> onComplete;

  @override
  State<QuizBattleRenderer> createState() => _QuizBattleRendererState();
}

class _QuizBattleRendererState extends State<QuizBattleRenderer> {
  final Stopwatch _watch = Stopwatch()..start();
  int _index = 0;
  int _score = 0;
  int _correct = 0;
  int _streak = 0;
  int _maxStreak = 0;
  String? _feedback;

  void _answer(String selected) {
    final item = widget.config.items[_index];
    final isRight = selected == item['correct_answer'].toString();
    final pts = (item['points'] as num?)?.toInt() ?? 100;
    setState(() {
      if (isRight) {
        _score += pts;
        _correct++;
        _streak++;
        _maxStreak = max(_maxStreak, _streak);
        _feedback = 'Tepat! ${item['explanation'] ?? ''}';
      } else {
        _streak = 0;
        _feedback = 'Belum tepat. Jawaban benar: ${item['correct_answer']}';
      }
    });

    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      if (_index + 1 >= widget.config.items.length) {
        _watch.stop();
        widget.onComplete(
          GamePlayResult(
            score: min(_score, widget.config.maxPossibleScore),
            maxScore: widget.config.maxPossibleScore,
            accuracyPercentage: (_correct / max(1, widget.config.items.length)) * 100,
            durationSeconds: max(1, _watch.elapsed.inSeconds),
            streakMax: _maxStreak,
          ),
        );
      } else {
        setState(() {
          _index++;
          _feedback = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.config.items[_index];
    final options = (item['options'] as List?)?.map((e) => e.toString()).toList() ?? const [];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppProgressIndicator(
            value: (_index + 1) / max(1, widget.config.items.length),
            label: 'Ronde ${_index + 1}/${widget.config.items.length} - Skor: $_score',
          ),
          const SizedBox(height: 18),
          Text((item['question'] ?? '').toString(), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          ...options.map((opt) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SecondaryButton(
                  label: opt,
                  onPressed: _feedback == null ? () => _answer(opt) : null,
                ),
              )),
          if (_feedback != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_feedback!, style: Theme.of(context).textTheme.bodyMedium),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// 2. WordMatchingRenderer
// ============================================================================
class WordMatchingRenderer extends StatefulWidget {
  const WordMatchingRenderer({super.key, required this.config, required this.onComplete});

  final GameConfigModel config;
  final ValueChanged<GamePlayResult> onComplete;

  @override
  State<WordMatchingRenderer> createState() => _WordMatchingRendererState();
}

class _WordMatchingRendererState extends State<WordMatchingRenderer> {
  final Stopwatch _watch = Stopwatch()..start();
  late List<Map<String, dynamic>> _rightItems;
  final Set<String> _matchedIds = {};
  String? _selectedLeftId;
  int _attempts = 0;
  int _score = 0;

  @override
  void initState() {
    super.initState();
    _rightItems = List<Map<String, dynamic>>.from(widget.config.items)..shuffle(Random(42));
  }

  void _pickRight(Map<String, dynamic> rightItem) {
    if (_selectedLeftId == null) return;
    _attempts++;
    final rightId = rightItem['id'].toString();
    if (_selectedLeftId == rightId) {
      final pts = (rightItem['points'] as num?)?.toInt() ?? 100;
      setState(() {
        _matchedIds.add(rightId);
        _selectedLeftId = null;
        _score += pts;
      });
      if (_matchedIds.length == widget.config.items.length) {
        _watch.stop();
        widget.onComplete(
          GamePlayResult(
            score: min(_score, widget.config.maxPossibleScore),
            maxScore: widget.config.maxPossibleScore,
            accuracyPercentage: (_matchedIds.length / max(1, _attempts)) * 100,
            durationSeconds: max(1, _watch.elapsed.inSeconds),
            streakMax: _matchedIds.length,
          ),
        );
      }
    } else {
      setState(() => _selectedLeftId = null);
      AppToast.show(context, message: 'Pasangan belum tepat, coba lagi.', variant: ToastVariant.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(widget.config.instructions, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 12),
        AppProgressIndicator(
          value: _matchedIds.length / max(1, widget.config.items.length),
          label: 'Cocok ${_matchedIds.length}/${widget.config.items.length}',
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: widget.config.items.map((item) {
                  final id = item['id'].toString();
                  final done = _matchedIds.contains(id);
                  final selected = _selectedLeftId == id;
                  return Card(
                    color: done
                        ? AppColors.success.withValues(alpha: 0.14)
                        : (selected ? AppColors.primary.withValues(alpha: 0.14) : null),
                    child: ListTile(
                      title: Text((item['left'] ?? '').toString(),
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      onTap: done ? null : () => setState(() => _selectedLeftId = id),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                children: _rightItems.map((item) {
                  final id = item['id'].toString();
                  final done = _matchedIds.contains(id);
                  return Card(
                    color: done ? AppColors.success.withValues(alpha: 0.14) : null,
                    child: ListTile(
                      title: Text((item['right'] ?? '').toString(),
                          style: const TextStyle(fontSize: 13)),
                      onTap: done ? null : () => _pickRight(item),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================================
// 3. TrueFalseRenderer
// ============================================================================
class TrueFalseRenderer extends StatefulWidget {
  const TrueFalseRenderer({super.key, required this.config, required this.onComplete});

  final GameConfigModel config;
  final ValueChanged<GamePlayResult> onComplete;

  @override
  State<TrueFalseRenderer> createState() => _TrueFalseRendererState();
}

class _TrueFalseRendererState extends State<TrueFalseRenderer> {
  final Stopwatch _watch = Stopwatch()..start();
  int _idx = 0;
  int _score = 0;
  int _correct = 0;

  void _choose(bool value) {
    final item = widget.config.items[_idx];
    final expected = item['is_true'] == true;
    final pts = (item['points'] as num?)?.toInt() ?? 100;
    if (value == expected) {
      _score += pts;
      _correct++;
    }
    if (_idx + 1 >= widget.config.items.length) {
      _watch.stop();
      widget.onComplete(
        GamePlayResult(
          score: min(_score, widget.config.maxPossibleScore),
          maxScore: widget.config.maxPossibleScore,
          accuracyPercentage: (_correct / max(1, widget.config.items.length)) * 100,
          durationSeconds: max(1, _watch.elapsed.inSeconds),
          streakMax: _correct,
        ),
      );
    } else {
      setState(() => _idx++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.config.items[_idx];
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          AppProgressIndicator(
            value: (_idx + 1) / max(1, widget.config.items.length),
            label: 'Pernyataan ${_idx + 1}/${widget.config.items.length}',
          ),
          const Spacer(),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                (item['statement'] ?? '').toString(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Salah',
                  icon: LucideIcons.x,
                  onPressed: () => _choose(false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PrimaryButton(
                  label: 'Benar',
                  icon: LucideIcons.check,
                  onPressed: () => _choose(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 4. MemoryCardRenderer
// ============================================================================
class MemoryCardRenderer extends StatefulWidget {
  const MemoryCardRenderer({super.key, required this.config, required this.onComplete});

  final GameConfigModel config;
  final ValueChanged<GamePlayResult> onComplete;

  @override
  State<MemoryCardRenderer> createState() => _MemoryCardRendererState();
}

class _MemoryCardRendererState extends State<MemoryCardRenderer> {
  final Stopwatch _watch = Stopwatch()..start();
  late List<({String pairId, String text})> _deck;
  final Set<int> _revealed = {};
  final Set<int> _matched = {};
  int _moves = 0;

  @override
  void initState() {
    super.initState();
    _deck = [
      for (final item in widget.config.items) ...[
        (pairId: item['id'].toString(), text: (item['card_a'] ?? '').toString()),
        (pairId: item['id'].toString(), text: (item['card_b'] ?? '').toString()),
      ],
    ]..shuffle(Random(7));
  }

  void _tapCard(int index) {
    if (_matched.contains(index) || _revealed.contains(index) || _revealed.length >= 2) return;
    setState(() => _revealed.add(index));

    if (_revealed.length == 2) {
      _moves++;
      final list = _revealed.toList();
      if (_deck[list[0]].pairId == _deck[list[1]].pairId) {
        setState(() {
          _matched.addAll(list);
          _revealed.clear();
        });
        if (_matched.length == _deck.length) {
          _watch.stop();
          final pairs = widget.config.items.length;
          widget.onComplete(
            GamePlayResult(
              score: widget.config.maxPossibleScore,
              maxScore: widget.config.maxPossibleScore,
              accuracyPercentage: min(100, (pairs / max(1, _moves)) * 100),
              durationSeconds: max(1, _watch.elapsed.inSeconds),
              streakMax: pairs,
            ),
          );
        }
      } else {
        Future<void>.delayed(const Duration(milliseconds: 650), () {
          if (mounted) setState(() => _revealed.clear());
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.35,
      ),
      itemCount: _deck.length,
      itemBuilder: (_, idx) {
        final open = _revealed.contains(idx) || _matched.contains(idx);
        return Card(
          color: _matched.contains(idx) ? AppColors.success.withValues(alpha: 0.14) : null,
          child: InkWell(
            onTap: () => _tapCard(idx),
            borderRadius: BorderRadius.circular(16),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: open
                    ? Text(_deck[idx].text, textAlign: TextAlign.center)
                    : const Icon(LucideIcons.circleHelp, size: 28, color: AppColors.primary),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// 5. CrosswordRenderer
// ============================================================================
class CrosswordRenderer extends StatefulWidget {
  const CrosswordRenderer({super.key, required this.config, required this.onComplete});

  final GameConfigModel config;
  final ValueChanged<GamePlayResult> onComplete;

  @override
  State<CrosswordRenderer> createState() => _CrosswordRendererState();
}

class _CrosswordRendererState extends State<CrosswordRenderer> {
  final Stopwatch _watch = Stopwatch()..start();
  final Map<int, TextEditingController> _controllers = {};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _checkAll() {
    final entries = widget.config.entries ?? const [];
    int correct = 0;
    for (int i = 0; i < entries.length; i++) {
      final expected = (entries[i]['answer'] ?? '').toString().trim().toUpperCase();
      final actual = (_controllers[i]?.text ?? '').trim().toUpperCase();
      if (actual == expected) correct++;
    }
    _watch.stop();
    final accuracy = (correct / max(1, entries.length)) * 100;
    final score = ((accuracy / 100.0) * widget.config.maxPossibleScore).round();
    widget.onComplete(
      GamePlayResult(
        score: score,
        maxScore: widget.config.maxPossibleScore,
        accuracyPercentage: accuracy,
        durationSeconds: max(1, _watch.elapsed.inSeconds),
        streakMax: correct,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.config.entries ?? const [];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(widget.config.instructions, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 14),
        ...List.generate(entries.length, (i) {
          final e = entries[i];
          final ctrl = _controllers.putIfAbsent(i, () => TextEditingController());
          final len = (e['answer'] ?? '').toString().length;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SubjectBadge(
                    label: '#${e['number']} ${e['direction'] == 'across' ? 'Mendatar' : 'Menurun'} ($len huruf)',
                  ),
                  const SizedBox(height: 8),
                  Text((e['clue'] ?? '').toString(), style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 10),
                  TextField(
                    controller: ctrl,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: len,
                    decoration: const InputDecoration(hintText: 'Ketik jawaban...'),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        PrimaryButton(label: 'Periksa Jawaban TTS', icon: LucideIcons.check, onPressed: _checkAll),
      ],
    );
  }
}

// ============================================================================
// 6. WordPuzzleRenderer
// ============================================================================
class WordPuzzleRenderer extends StatefulWidget {
  const WordPuzzleRenderer({super.key, required this.config, required this.onComplete});

  final GameConfigModel config;
  final ValueChanged<GamePlayResult> onComplete;

  @override
  State<WordPuzzleRenderer> createState() => _WordPuzzleRendererState();
}

class _WordPuzzleRendererState extends State<WordPuzzleRenderer> {
  final Stopwatch _watch = Stopwatch()..start();
  final _answerCtrl = TextEditingController();
  int _idx = 0;
  int _correct = 0;
  int _score = 0;

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  void _checkWord() {
    final item = widget.config.items[_idx];
    final expected = (item['target_word'] ?? '').toString().trim().toUpperCase();
    final pts = (item['points'] as num?)?.toInt() ?? 100;
    if (_answerCtrl.text.trim().toUpperCase() == expected) {
      _correct++;
      _score += pts;
    }
    _answerCtrl.clear();

    if (_idx + 1 >= widget.config.items.length) {
      _watch.stop();
      widget.onComplete(
        GamePlayResult(
          score: min(_score, widget.config.maxPossibleScore),
          maxScore: widget.config.maxPossibleScore,
          accuracyPercentage: (_correct / max(1, widget.config.items.length)) * 100,
          durationSeconds: max(1, _watch.elapsed.inSeconds),
          streakMax: _correct,
        ),
      );
    } else {
      setState(() => _idx++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.config.items[_idx];
    final word = (item['target_word'] ?? '').toString().toUpperCase();
    final letters = word.split('')..shuffle(Random(_idx + 13));

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppProgressIndicator(
            value: (_idx + 1) / max(1, widget.config.items.length),
            label: 'Kata ${_idx + 1}/${widget.config.items.length}',
          ),
          const SizedBox(height: 18),
          Text((item['clue'] ?? '').toString(), style: Theme.of(context).textTheme.titleLarge),
          if (item['hint'] != null) ...[
            const SizedBox(height: 6),
            Text('Petunjuk: ${item['hint']}', style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: letters
                .map((ch) => Chip(
                      label: Text(ch, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ))
                .toList(),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _answerCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: 'Susun kata di sini...'),
          ),
          const SizedBox(height: 18),
          PrimaryButton(label: 'Kirim Jawaban', icon: LucideIcons.check, onPressed: _checkWord),
        ],
      ),
    );
  }
}
