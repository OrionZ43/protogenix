import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protogenix/features/player/presentation/providers/player_provider.dart';

void showSleepTimerSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _SleepTimerSheet(),
  );
}

class _SleepTimerSheet extends ConsumerWidget {
  const _SleepTimerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerProvider);
    final isActive = state.sleepTimerActive;
    final stopAfterTrack = state.stopAfterTrack;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(200),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: Colors.white.withAlpha(20))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 24),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(40),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'ТАЙМЕР СНА',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 24),
              if (isActive) ...[
                Text(
                  stopAfterTrack
                      ? 'Остановка после этого трека'
                      : 'Таймер активен',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 32),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    ref.read(playerProvider.notifier).cancelSleepTimer();
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withAlpha(40),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.redAccent.withAlpha(80)),
                    ),
                    child: const Text(
                      'Отменить таймер',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [5, 10, 15, 20, 30, 45, 60, 90]
                      .map((minutes) => _PresetCapsule(
                            label: '$minutes мин',
                            onTap: () {
                              HapticFeedback.lightImpact();
                              ref
                                  .read(playerProvider.notifier)
                                  .startSleepTimer(Duration(minutes: minutes));
                              Navigator.of(context).pop();
                            },
                          ))
                      .toList(),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    ref.read(playerProvider.notifier).setStopAfterTrack();
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(20),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withAlpha(30)),
                    ),
                    child: const Text(
                      'По окончании трека',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetCapsule extends StatelessWidget {
  const _PresetCapsule({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withAlpha(25)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
