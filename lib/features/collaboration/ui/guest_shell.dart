import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:yoloit/core/theme/app_color_scheme.dart';
import '../bloc/collaboration_cubit.dart';
import '../bloc/collaboration_state.dart';
import '../collaboration_ports.dart';
import 'web_mindmap_canvas.dart';

/// Full-screen shell shown when the app runs in browser / non-desktop mode.
/// - Before connect: shows a connect form
/// - After connect:  shows the live mindmap canvas (read/write via WebSocket)
class GuestShell extends StatefulWidget {
  const GuestShell({super.key});

  @override
  State<GuestShell> createState() => _GuestShellState();
}

class _GuestShellState extends State<GuestShell> {
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  final _nameCtrl = TextEditingController(text: 'Remote Guest');
  bool _autoConnectPending = false;

  @override
  void initState() {
    super.initState();
    final autoHost = _inferHost();
    final autoPort = _inferWsPort();
    _hostCtrl = TextEditingController(text: autoHost);
    _portCtrl = TextEditingController(text: '$autoPort');
    // Auto-connect when page is served with a known host (local or LAN).
    if (autoHost.isNotEmpty) {
      _autoConnectPending = true;
    }
  }

  /// On web: reads the page URL host so the connect form is pre-filled.
  static String _inferHost() {
    try {
      final host = Uri.base.host;
      if (host.isEmpty) return '';
      return host;
    } catch (_) {
      return '';
    }
  }

  static int _inferWsPort() {
    try {
      final rawPort = Uri.base.queryParameters['wsPort'] ?? '';
      return int.tryParse(rawPort) ?? kDefaultWsPort;
    } catch (_) {
      return kDefaultWsPort;
    }
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect(CollaborationCubit cubit) async {
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? kDefaultWsPort;
    if (host.isEmpty) return;
    await cubit.connect(host, port: port);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CollaborationCubit, CollaborationState>(
      builder: (ctx, collab) {
        // Auto-connect once when served from localhost
        if (_autoConnectPending && collab.mode == CollaborationMode.idle) {
          _autoConnectPending = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _connect(ctx.read<CollaborationCubit>());
          });
        }
        if (collab.mode == CollaborationMode.connected) {
          return _buildCanvas(ctx, collab);
        }
        return _buildConnectScreen(ctx, collab);
      },
    );
  }

  // ── Connect screen ────────────────────────────────────────────────────────

  Widget _buildConnectScreen(BuildContext ctx, CollaborationState collab) {
    final cubit = ctx.read<CollaborationCubit>();
    final colors = ctx.appColors;
    return Scaffold(
      backgroundColor: colors.terminalBackground,
      body: Center(
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(36),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border, width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x60000000),
                blurRadius: 40,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Logo / title ─────────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4B9EFF).withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF4B9EFF).withAlpha(80),
                      ),
                    ),
                    child: const Icon(
                      Icons.hub_rounded,
                      color: Color(0xFF4B9EFF),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'YoLoIT Space',
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Connect to a running desktop session',
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.5),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // ── Fields ────────────────────────────────────────────────
              _label('Host IP'),
              const SizedBox(height: 6),
              _field(_hostCtrl, 'e.g. 192.168.1.42 or localhost'),
              const SizedBox(height: 16),
              _label('Port'),
              const SizedBox(height: 6),
              _field(_portCtrl, '$kDefaultWsPort', number: true),
              const SizedBox(height: 16),
              _label('Your name'),
              const SizedBox(height: 6),
              _field(_nameCtrl, 'Guest'),
              const SizedBox(height: 28),

              // ── Error message ────────────────────────────────────────
              if (collab.error.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF4F6A).withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFFF4F6A).withAlpha(60),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Color(0xFFFF4F6A),
                        size: 14,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          collab.error,
                          style: const TextStyle(
                            color: Color(0xFFFF4F6A),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Connect button ────────────────────────────────────────
              SizedBox(
                height: 44,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4B9EFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => _connect(cubit),
                  child: const Text(
                    'Connect to Space',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),

              // ── Hint ─────────────────────────────────────────────────
              const SizedBox(height: 20),
              Text(
                'The YoLoIT desktop app must be running and sharing the Space\n'
                '(toolbar → Share → Start Hosting).',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: TextStyle(
      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
      fontSize: 12,
      fontWeight: FontWeight.w500,
    ),
  );

  Widget _field(TextEditingController c, String hint, {bool number = false}) =>
      TextField(
        controller: c,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 14,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            fontSize: 14,
          ),
          filled: true,
          fillColor: context.appColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: context.appColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: context.appColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF4B9EFF), width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
      );

  // ── Connected canvas ─────────────────────────────────────────────────────

  Widget _buildCanvas(BuildContext ctx, CollaborationState collab) {
    return Scaffold(
      backgroundColor: ctx.appColors.terminalBackground,
      body: Column(
        children: [
          _buildTopBar(ctx, collab),
          const Expanded(child: WebMindMapCanvas()),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext ctx, CollaborationState collab) {
    return Container(
      height: 44,
      color: ctx.appColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.hub_rounded, color: Color(0xFF4B9EFF), size: 16),
          const SizedBox(width: 8),
          Text(
            'YoLoIT Space',
            style: TextStyle(
              color: Theme.of(ctx).colorScheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF00FF9F).withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF00FF9F).withAlpha(60),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF00FF9F),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'Connected · ${collab.address}',
                  style: const TextStyle(
                    color: Color(0xFF00FF9F),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (collab.peerCount > 0) ...[
            const SizedBox(width: 12),
            Text(
              '${collab.peerCount} peer${collab.peerCount > 1 ? 's' : ''}',
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.5),
                fontSize: 11,
              ),
            ),
          ],
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.link_off, size: 14),
            label: const Text('Disconnect'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.5),
              textStyle: const TextStyle(fontSize: 12),
            ),
            onPressed: () => ctx.read<CollaborationCubit>().disconnect(),
          ),
        ],
      ),
    );
  }
}
