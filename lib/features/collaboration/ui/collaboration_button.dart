import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:yoloit/core/theme/app_color_scheme.dart';
import '../bloc/collaboration_cubit.dart';
import '../bloc/collaboration_state.dart';
import '../collaboration_ports.dart';

/// Toolbar button that opens the collaboration (Share Space) popover.
class CollaborationButton extends StatelessWidget {
  const CollaborationButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CollaborationCubit, CollaborationState>(
      builder: (ctx, state) {
        final color = state.isHosting
            ? const Color(0xFF34D399)
            : state.isGuest
            ? const Color(0xFF60A5FA)
            : state.isStartingHost
            ? const Color(0xFF7C3AED)
            : const Color(0xFF9AA3BF);
        return _CollabToolBtn(
          icon: Icons.people_outline_rounded,
          tooltip: state.isStartingHost
              ? 'Starting Share Space…'
              : state.isIdle
              ? 'Share Space'
              : state.address,
          color: color,
          badge: state.peerCount > 0 ? '${state.peerCount}' : null,
          onTap: () => _showDialog(ctx),
        );
      },
    );
  }

  void _showDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: const Color(0x66000000),
      builder: (_) => BlocProvider.value(
        value: context.read<CollaborationCubit>(),
        child: const _CollaborationDialog(),
      ),
    );
  }
}

// ── Dialog ─────────────────────────────────────────────────────────────────

class _CollaborationDialog extends StatefulWidget {
  const _CollaborationDialog();

  @override
  State<_CollaborationDialog> createState() => _CollaborationDialogState();
}

class _CollaborationDialogState extends State<_CollaborationDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _ipCtrl = TextEditingController();
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _ipCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 420,
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0xBB000000),
                blurRadius: 32,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(
                      Icons.people_rounded,
                      size: 18,
                      color: Color(0xFF7C3AED),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Share Space',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 16,
                        color: Theme.of(context).textTheme.bodySmall?.color ??
                            Theme.of(context).colorScheme.onSurface,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Body — changes depending on collaboration state.
                BlocBuilder<CollaborationCubit, CollaborationState>(
                  builder: (ctx, state) {
                    if (state.isHosting) {
                      return _HostActiveView(state: state);
                    }
                    if (state.isGuest) {
                      return _GuestActiveView(state: state);
                    }
                    return _IdleView(
                      tabs: _tabs,
                      ipCtrl: _ipCtrl,
                      connecting: _connecting,
                      onConnecting: (v) => setState(() => _connecting = v),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Idle ───────────────────────────────────────────────────────────────────

class _IdleView extends StatelessWidget {
  const _IdleView({
    required this.tabs,
    required this.ipCtrl,
    required this.connecting,
    required this.onConnecting,
  });
  final TabController tabs;
  final TextEditingController ipCtrl;
  final bool connecting;
  final void Function(bool) onConnecting;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tab bar
        Container(
          height: 34,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: TabBar(
            controller: tabs,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              color: colors.surfaceElevated,
              borderRadius: BorderRadius.circular(6),
            ),
            labelColor: Theme.of(context).colorScheme.onSurface,
            unselectedLabelColor:
                Theme.of(context).textTheme.bodySmall?.color ??
                Theme.of(context).colorScheme.onSurface,
            labelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: 'Host a Space'),
              Tab(text: 'Join a Space'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 140,
          child: TabBarView(
            controller: tabs,
            children: [
              _HostTab(),
              _GuestTab(
                ctrl: ipCtrl,
                connecting: connecting,
                onConnecting: onConnecting,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HostTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CollaborationCubit, CollaborationState>(
      builder: (ctx, state) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Start a server so others on your local network can connect '
            'and mirror your Mindmap board in real time.',
            style: TextStyle(
              color: Color(0xFF9AA3BF),
              fontSize: 12,
              height: 1.5,
            ),
          ),
          if (state.isStartingHost)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.sync, size: 12, color: Color(0xFF7C3AED)),
                  SizedBox(width: 6),
                  Text(
                    'Starting host and probing available ports…',
                    style: TextStyle(color: Color(0xFFB794F6), fontSize: 11),
                  ),
                ],
              ),
            ),
          if (state.error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                state.error,
                style: const TextStyle(color: Color(0xFFF87171), fontSize: 11),
              ),
            ),
          const Spacer(),
          _PrimaryBtn(
            label: state.isStartingHost ? 'Starting…' : 'Start Hosting',
            icon: Icons.wifi_tethering_rounded,
            onTap: state.isStartingHost
                ? null
                : () => ctx.read<CollaborationCubit>().startHosting(),
          ),
        ],
      ),
    );
  }
}

class _GuestTab extends StatelessWidget {
  const _GuestTab({
    required this.ctrl,
    required this.connecting,
    required this.onConnecting,
  });
  final TextEditingController ctrl;
  final bool connecting;
  final void Function(bool) onConnecting;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CollaborationCubit, CollaborationState>(
      builder: (ctx, state) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DarkTextField(
            controller: ctrl,
            hint: 'Host IP or IP:port  e.g. 192.168.1.10',
            enabled: !connecting,
          ),
          if (state.error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                state.error,
                style: const TextStyle(color: Color(0xFFF87171), fontSize: 11),
              ),
            ),
          const Spacer(),
          _PrimaryBtn(
            label: connecting ? 'Connecting…' : 'Connect',
            icon: Icons.lan_outlined,
            onTap: connecting
                ? null
                : () async {
                    final raw = ctrl.text.trim();
                    if (raw.isEmpty) return;
                    // Allow "192.168.1.10:40401" — extract host and port
                    final colonIdx = raw.lastIndexOf(':');
                    String host = raw;
                    int port = kDefaultWsPort;
                    if (colonIdx > 0) {
                      final maybePart = raw.substring(colonIdx + 1);
                      final maybePort = int.tryParse(maybePart);
                      if (maybePort != null) {
                        host = raw.substring(0, colonIdx);
                        port = maybePort;
                      }
                    }
                    onConnecting(true);
                    await ctx.read<CollaborationCubit>().connect(
                      host,
                      port: port,
                    );
                    onConnecting(false);
                    if (ctx.mounted &&
                        ctx.read<CollaborationCubit>().state.isGuest) {
                      Navigator.pop(ctx);
                    }
                  },
          ),
        ],
      ),
    );
  }
}

// ── Host active ────────────────────────────────────────────────────────────

class _HostActiveView extends StatelessWidget {
  const _HostActiveView({required this.state});
  final CollaborationState state;

  Future<void> _openLocally() async {
    final url = state.localUrl;
    if (url.isEmpty) return;
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      } else if (Platform.isWindows) {
        await Process.run('start', [url], runInShell: true);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final remoteUrl = state.webClientUrl;
    final localUrl = state.localUrl;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final mutedColor =
        Theme.of(context).textTheme.bodySmall?.color ?? onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Status badge ────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1A12),
            border: Border.all(color: const Color(0x4034D399)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.wifi_tethering_rounded,
                size: 14,
                color: Color(0xFF34D399),
              ),
              const SizedBox(width: 8),
              const Text(
                'Hosting active',
                style: TextStyle(
                  color: Color(0xFF34D399),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (state.peers.isNotEmpty)
                Row(
                  children: [
                    const Icon(
                      Icons.person_outline,
                      size: 13,
                      color: Color(0xFF60A5FA),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${state.peerCount}',
                      style: const TextStyle(
                        color: Color(0xFF60A5FA),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'connected',
                      style: TextStyle(color: mutedColor, fontSize: 11),
                    ),
                  ],
                ),
            ],
          ),
        ),

        if (remoteUrl.isNotEmpty) ...[
          const SizedBox(height: 12),

          // ── Open on THIS Mac ──────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0F1A),
              border: Border.all(color: const Color(0xFF1E3A20)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.laptop_mac,
                  size: 14,
                  color: Color(0xFF34D399),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Open on this Mac:',
                        style: TextStyle(
                          color: Color(0xFF34D399),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        localUrl,
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                _UrlActionBtn(
                  icon: Icons.open_in_browser,
                  tooltip: 'Open in browser on this Mac',
                  onTap: _openLocally,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── Share URL for remote devices ─────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: context.appColors.surface,
              border: Border.all(color: const Color(0xFF3B5BDB)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.share, size: 12, color: Color(0xFF7B9EFF)),
                    SizedBox(width: 6),
                    Text(
                      'Share with other devices (same Wi-Fi):',
                      style: TextStyle(
                        color: Color(0xFF7B9EFF),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        remoteUrl,
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _UrlActionBtn(
                      icon: Icons.copy,
                      tooltip: 'Copy URL',
                      onTap: () =>
                          Clipboard.setData(ClipboardData(text: remoteUrl)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],

        // ── Peers list ───────────────────────────────────────────────
        if (state.peers.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Connected peers:',
            style: TextStyle(
              color: mutedColor,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          for (final e in state.peers.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 13,
                    color: Color(
                      int.tryParse(
                            e.value.color.replaceFirst('#', '0xFF'),
                          ) ??
                          0xFF60A5FA,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    e.value.name.isNotEmpty ? e.value.name : e.key,
                    style: TextStyle(
                      color: onSurface,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
        ] else ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.hourglass_empty, size: 12, color: mutedColor),
              const SizedBox(width: 6),
              Text(
                'Waiting for peers to connect…',
                style: TextStyle(color: mutedColor, fontSize: 12),
              ),
            ],
          ),
        ],

        const SizedBox(height: 14),
        _SecondaryBtn(
          label: 'Stop Hosting',
          icon: Icons.wifi_tethering_off_rounded,
          color: const Color(0xFFF87171),
          onTap: () {
            context.read<CollaborationCubit>().stopHosting();
            Navigator.pop(context);
          },
        ),
      ],
    );
  }
}

class _UrlActionBtn extends StatelessWidget {
  const _UrlActionBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: context.appColors.surfaceElevated,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14, color: const Color(0xFF7B9EFF)),
      ),
    ),
  );
}

// ── Guest active ───────────────────────────────────────────────────────────

class _GuestActiveView extends StatelessWidget {
  const _GuestActiveView({required this.state});
  final CollaborationState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1020),
            border: Border.all(color: const Color(0x4060A5FA)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.lan_outlined,
                size: 16,
                color: Color(0xFF60A5FA),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Connected',
                    style: TextStyle(
                      color: Color(0xFF60A5FA),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    state.address,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 14,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SecondaryBtn(
          label: 'Disconnect',
          icon: Icons.link_off_rounded,
          color: const Color(0xFFF87171),
          onTap: () {
            context.read<CollaborationCubit>().disconnect();
            Navigator.pop(context);
          },
        ),
      ],
    );
  }
}

// ── Shared small widgets ───────────────────────────────────────────────────

class _PrimaryBtn extends StatelessWidget {
  const _PrimaryBtn({required this.label, required this.icon, this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFF7C3AED) : const Color(0xFF2A2A40),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryBtn extends StatelessWidget {
  const _SecondaryBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          border: Border.all(color: color.withAlpha(100)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DarkTextField extends StatelessWidget {
  const _DarkTextField({
    required this.controller,
    required this.hint,
    this.enabled = true,
  });
  final TextEditingController controller;
  final String hint;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return TextField(
      controller: controller,
      enabled: enabled,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 13,
        fontFamily: 'monospace',
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: Theme.of(context).textTheme.bodySmall?.color ??
              Theme.of(context).colorScheme.onSurface,
          fontSize: 12,
        ),
        filled: true,
        fillColor: colors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF7C3AED)),
        ),
      ),
    );
  }
}

// ── Toolbar icon button ────────────────────────────────────────────────────

class _CollabToolBtn extends StatefulWidget {
  const _CollabToolBtn({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
    this.badge,
  });
  final IconData icon;
  final String tooltip;
  final Color color;
  final String? badge;
  final VoidCallback? onTap;

  @override
  State<_CollabToolBtn> createState() => _CollabToolBtnState();
}

class _CollabToolBtnState extends State<_CollabToolBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: _hovered
                  ? colors.surfaceElevated
                  : const Color(0xFF1A1E2A),
              border: Border.all(
                color: _hovered
                    ? widget.color.withAlpha(160)
                    : colors.border,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(widget.icon, size: 14, color: widget.color),
                if (widget.badge != null)
                  Positioned(
                    top: -6,
                    right: -8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF34D399),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        widget.badge!,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
