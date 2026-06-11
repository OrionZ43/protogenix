// lib/core/widgets/window_title_bar.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../../features/player/presentation/providers/palette_provider.dart';
import 'neon_logo.dart';

class WindowTitleBar extends ConsumerStatefulWidget
    implements PreferredSizeWidget {
  const WindowTitleBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(32);

  @override
  ConsumerState<WindowTitleBar> createState() => _WindowTitleBarState();
}

class _WindowTitleBarState extends ConsumerState<WindowTitleBar>
    with WindowListener {
  bool _isMaximized = false;
  bool get _isMacOS => Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _checkMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _checkMaximized() async {
    final maximized = await windowManager.isMaximized();
    if (mounted) setState(() => _isMaximized = maximized);
  }

  @override
  void onWindowMaximize() => setState(() => _isMaximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(paletteProvider);

    return Material(
      color: Colors.transparent,
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color.lerp(const Color(0xFF080810), palette.primary, 0.25) ??
                  const Color(0xFF080810),
              const Color(0xFF080810),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          border: Border(
            bottom: BorderSide(color: Colors.white.withAlpha(15)),
          ),
        ),
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment.stretch, // Растягиваем на всю высоту
          children: [
            // 1. macOS Кнопки (отдельно от DragToMoveArea = моментальный клик)
            if (_isMacOS) ...[
              const SizedBox(width: 12),
              Align(
                alignment: Alignment.center,
                child: _MacOsControls(isMaximized: _isMaximized),
              ),
              const SizedBox(width: 16),
            ],

            // 2. Зона перетаскивания окна
            Expanded(
              child: DragToMoveArea(
                child: Container(
                  // Прозрачный цвет нужен, чтобы Flutter "видел" эту зону для мыши
                  color: Colors.transparent,
                  alignment: Alignment.centerLeft,
                  padding: EdgeInsets.only(left: _isMacOS ? 0 : 16),
                  child: const _Logo(),
                ),
              ),
            ),

            // 3. Windows/Linux Кнопки (отдельно от DragToMoveArea = моментальный клик)
            if (!_isMacOS) _WindowsControls(isMaximized: _isMaximized),
          ],
        ),
      ),
    );
  }
}

// ── Логотип ──────────────────────────────────────────────────────────────────

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        NeonLogo(size: 22),
        SizedBox(width: 8),
        Text(
          'Protogenix',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// ── Windows / Linux кнопки ───────────────────────────────────────────────────

class _WindowsControls extends StatelessWidget {
  const _WindowsControls({required this.isMaximized});
  final bool isMaximized;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WinBtn(icon: Icons.minimize_rounded, onTap: windowManager.minimize),
        _WinBtn(
          icon: isMaximized
              ? Icons.filter_none_rounded
              : Icons.crop_square_rounded,
          iconSize: isMaximized ? 12 : 14,
          onTap: () => isMaximized
              ? windowManager.unmaximize()
              : windowManager.maximize(),
        ),
        _WinBtn(
          icon: Icons.close_rounded,
          isClose: true,
          onTap: windowManager.close,
        ),
      ],
    );
  }
}

class _WinBtn extends StatefulWidget {
  const _WinBtn(
      {required this.icon,
      required this.onTap,
      this.isClose = false,
      this.iconSize = 16});
  final IconData icon;
  final VoidCallback onTap;
  final bool isClose;
  final double iconSize;

  @override
  State<_WinBtn> createState() => _WinBtnState();
}

class _WinBtnState extends State<_WinBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 40,
          color: _hover
              ? (widget.isClose
                  ? const Color(0xFFE81123)
                  : Colors.white.withValues(alpha: 0.08))
              : Colors.transparent,
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: _hover && widget.isClose ? Colors.white : Colors.white54,
          ),
        ),
      ),
    );
  }
}

// ── macOS кнопки ─────────────────────────────────────────────────────────────

class _MacOsControls extends StatelessWidget {
  const _MacOsControls({required this.isMaximized});
  final bool isMaximized;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MacBtn(
            color: const Color(0xFFFF5F57),
            icon: Icons.close_rounded,
            onTap: windowManager.close),
        const SizedBox(width: 8),
        _MacBtn(
            color: const Color(0xFFFFBD2E),
            icon: Icons.minimize_rounded,
            onTap: windowManager.minimize),
        const SizedBox(width: 8),
        _MacBtn(
          color: const Color(0xFF28CA42),
          icon: isMaximized
              ? Icons.fullscreen_exit_rounded
              : Icons.fullscreen_rounded,
          onTap: () => isMaximized
              ? windowManager.unmaximize()
              : windowManager.maximize(),
        ),
      ],
    );
  }
}

class _MacBtn extends StatefulWidget {
  const _MacBtn({required this.color, required this.icon, required this.onTap});
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_MacBtn> createState() => _MacBtnState();
}

class _MacBtnState extends State<_MacBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _hover ? widget.color : widget.color.withValues(alpha: 0.8),
            boxShadow: _hover
                ? [
                    BoxShadow(
                        color: widget.color.withValues(alpha: 0.5),
                        blurRadius: 4)
                  ]
                : null,
          ),
          child:
              _hover ? Icon(widget.icon, size: 8, color: Colors.black45) : null,
        ),
      ),
    );
  }
}
