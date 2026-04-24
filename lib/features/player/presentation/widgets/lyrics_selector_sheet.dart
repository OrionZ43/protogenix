import 'package:flutter/material.dart';
import '../../../library/domain/lyrics_models.dart';

/// Открывает шторку выбора текста и возвращает выбранный [LyricsMetadata].
/// Возвращает null если пользователь закрыл шторку без выбора.
Future<LyricsMetadata?> showLyricsSelectorSheet(
  BuildContext context,
  List<ScoredLyric> candidates,
) {
  return showModalBottomSheet<LyricsMetadata>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _LyricsSelectorSheet(candidates: candidates),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// ШТОРКА ВЫБОРА
// ═══════════════════════════════════════════════════════════════════════════

class _LyricsSelectorSheet extends StatelessWidget {
  const _LyricsSelectorSheet({required this.candidates});

  final List<ScoredLyric> candidates;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E18),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: Colors.white.withAlpha(18),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Ручка ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(50),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

          // ── Заголовок ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
            child: Row(
              children: [
                const Icon(Icons.lyrics_rounded,
                    color: Colors.white54, size: 18),
                const SizedBox(width: 10),
                const Text(
                  'Выбери текст песни',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${candidates.length} вариантов',
                  style: TextStyle(
                    color: Colors.white.withAlpha(60),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          Divider(color: Colors.white.withAlpha(15), height: 16),

          // ── Список кандидатов ──────────────────────────────────────────
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              itemCount: candidates.length,
              separatorBuilder: (_, __) => Divider(
                color: Colors.white.withAlpha(10),
                height: 1,
                indent: 16,
              ),
              itemBuilder: (context, index) {
                final item = candidates[index];
                return _CandidateTile(
                  scored: item,
                  isTop: index == 0,
                  onTap: () => Navigator.of(context).pop(item.metadata),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ПЛИТКА КАНДИДАТА
// ═══════════════════════════════════════════════════════════════════════════

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.scored,
    required this.isTop,
    required this.onTap,
  });

  final ScoredLyric scored;
  final bool isTop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = scored.metadata;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: Colors.white.withAlpha(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: isTop
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white.withAlpha(8),
                  border: Border.all(
                    color: Colors.white.withAlpha(20),
                    width: 1,
                  ),
                )
              : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Иконка типа ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 12),
                child: _TypeIcon(type: meta.type),
              ),

              // ── Название и артист ────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            meta.trackName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isTop) ...[
                          const SizedBox(width: 6),
                          _TopBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      meta.artistName,
                      style: TextStyle(
                        color: Colors.white.withAlpha(120),
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),

                    // ── Бейджи ─────────────────────────────────────────
                    Row(
                      children: [
                        _TypeBadge(type: meta.type),
                        const SizedBox(width: 6),
                        _SourceBadge(source: meta.source),
                        if (meta.durationMs != null) ...[
                          const SizedBox(width: 6),
                          _DurationBadge(durationMs: meta.durationMs!),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // ── Score ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: _ScoreWidget(score: scored.score),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

/// Круглая иконка типа текста
class _TypeIcon extends StatelessWidget {
  const _TypeIcon({required this.type});
  final LyricsType type;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: switch (type) {
            LyricsType.syllable => [
                const Color(0xFFE040FB),
                const Color(0xFF7C4DFF),
              ],
            LyricsType.enhanced => [
                const Color(0xFFFFD700),
                const Color(0xFFFFA500),
              ],
            LyricsType.synced => [
                const Color(0xFF4FC3F7),
                const Color(0xFF0288D1),
              ],
            LyricsType.plain => [
                const Color(0xFF78909C),
                const Color(0xFF546E7A),
              ],
          },
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(
        switch (type) {
          LyricsType.syllable => Icons.record_voice_over_rounded,
          LyricsType.enhanced => Icons.auto_awesome_rounded,
          LyricsType.synced => Icons.access_time_rounded,
          LyricsType.plain => Icons.article_outlined,
        },
        color: Colors.white,
        size: 18,
      ),
    );
  }
}

/// Бейдж формата текста
class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});
  final LyricsType type;

  @override
  Widget build(BuildContext context) {
    final (label, colors) = switch (type) {
      LyricsType.syllable => (
          'Syllable',
          [const Color(0xFFE040FB), const Color(0xFF7C4DFF)],
        ),
      LyricsType.enhanced => (
          'Word-by-Word',
          [const Color(0xFFFFD700), const Color(0xFFFF8C00)],
        ),
      LyricsType.synced => (
          'Synced',
          [const Color(0xFF29B6F6), const Color(0xFF0277BD)],
        ),
      LyricsType.plain => (
          'Plain',
          [const Color(0xFF607D8B), const Color(0xFF455A64)],
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Бейдж источника
class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});
  final String source;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: Colors.white.withAlpha(15),
        border: Border.all(color: Colors.white.withAlpha(25)),
      ),
      child: Text(
        source,
        style: TextStyle(
          color: Colors.white.withAlpha(140),
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Бейдж длительности
class _DurationBadge extends StatelessWidget {
  const _DurationBadge({required this.durationMs});
  final int durationMs;

  @override
  Widget build(BuildContext context) {
    final totalSec = durationMs ~/ 1000;
    final minutes = totalSec ~/ 60;
    final seconds = totalSec % 60;
    final label = '$minutes:${seconds.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: Colors.white.withAlpha(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded,
              size: 10, color: Colors.white.withAlpha(80)),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withAlpha(100),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

/// Виджет скора — цвет зависит от уверенности
class _ScoreWidget extends StatelessWidget {
  const _ScoreWidget({required this.score});
  final double score;

  @override
  Widget build(BuildContext context) {
    final Color color = score >= 80
        ? const Color(0xFF66BB6A) // зелёный — высокая уверенность
        : score >= 50
            ? const Color(0xFFFFA726) // оранжевый — средняя
            : const Color(0xFFEF5350); // красный — низкая

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          score.toStringAsFixed(0),
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          'score',
          style: TextStyle(
            color: Colors.white.withAlpha(50),
            fontSize: 9,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

/// Бейдж "Лучший вариант" для первого элемента
class _TopBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        gradient: const LinearGradient(
          colors: [Color(0xFF7B5EA7), Color(0xFF4A90D9)],
        ),
      ),
      child: const Text(
        'TOP',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
