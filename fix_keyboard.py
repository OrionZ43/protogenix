with open('lib/app/app_shell.dart', 'r') as f:
    content = f.read()

import re

search = """  @override
  Widget build(BuildContext context) {
    // Breakpoint: Fold (~600px width).
    // Больше 600px — показываем ExpandedShell (NavigationRail слева).
    // Меньше 600px — CompactShell (BottomNavigationBar).
    final isExpanded = MediaQuery.sizeOf(context).width >= kFoldBreakpoint;

    return isExpanded ? const _ExpandedShell() : const _CompactShell();
  }"""

replace = """  @override
  Widget build(BuildContext context) {
    // Breakpoint: Fold (~600px width).
    // Больше 600px — показываем ExpandedShell (NavigationRail слева).
    // Меньше 600px — CompactShell (BottomNavigationBar).
    final isExpanded = MediaQuery.sizeOf(context).width >= kFoldBreakpoint;

    return FocusableActionDetector(
      autofocus: true,
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.space): const PlayPauseIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowRight): const NextTrackIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowLeft): const PreviousTrackIntent(),
      },
      actions: {
        PlayPauseIntent: CallbackAction<PlayPauseIntent>(onInvoke: (_) {
          ref.read(playerProvider.notifier).playPause();
          return null;
        }),
        NextTrackIntent: CallbackAction<NextTrackIntent>(onInvoke: (_) {
          ref.read(playerProvider.notifier).next();
          return null;
        }),
        PreviousTrackIntent: CallbackAction<PreviousTrackIntent>(onInvoke: (_) {
          ref.read(playerProvider.notifier).previous();
          return null;
        }),
      },
      child: isExpanded ? const _ExpandedShell() : const _CompactShell(),
    );
  }"""

if search in content:
    content = content.replace(search, replace)

with open('lib/app/app_shell.dart', 'w') as f:
    f.write(content)
