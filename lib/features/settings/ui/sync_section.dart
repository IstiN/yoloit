import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_colors.dart';

enum SyncMethod { none, git, googleDrive, customPath }

/// Settings section for workspace sync configuration.
class SyncSection extends StatefulWidget {
  const SyncSection({super.key});

  @override
  State<SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends State<SyncSection> {
  SyncMethod _method = SyncMethod.none;

  // Git
  final _gitRemoteCtrl = TextEditingController();
  final _gitBranchCtrl = TextEditingController(text: 'yoloit-sync');
  bool _autoPush = false;

  // Custom path
  final _customPathCtrl = TextEditingController();

  // Google Drive
  bool _gdriveConnected = false;
  final _gdriveFolderCtrl = TextEditingController(text: '/YoLoIT/sync');

  String? _lastSynced;

  @override
  void dispose() {
    _gitRemoteCtrl.dispose();
    _gitBranchCtrl.dispose();
    _customPathCtrl.dispose();
    _gdriveFolderCtrl.dispose();
    super.dispose();
  }

  void _showComingSoon(String action) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$action coming soon')));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sync method radios
        _buildMethodRadios(colors),
        const SizedBox(height: 16),
        // Conditional settings
        if (_method == SyncMethod.git) _buildGitSection(colors),
        if (_method == SyncMethod.googleDrive) _buildGDriveSection(colors),
        if (_method == SyncMethod.customPath) _buildCustomPathSection(colors),
        const SizedBox(height: 16),
        // Last synced
        Text(
          _lastSynced == null
              ? 'Last synced: never'
              : 'Last synced: $_lastSynced',
          style: TextStyle(
            color:
                Theme.of(context).textTheme.bodySmall?.color ??
                Theme.of(context).colorScheme.onSurface,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 16),
        // What gets synced
        _buildSyncInfoExpander(colors),
      ],
    );
  }

  // ─── Sync method radios ───────────────────────────────────────────────────

  Widget _buildMethodRadios(AppColorScheme colors) {
    Widget radio(SyncMethod value, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Radio<SyncMethod>(
            value: value,
            groupValue: _method,
            onChanged: (v) => setState(() => _method = v!),
            activeColor: colors.primary,
          ),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 12),
        ],
      );
    }

    return Wrap(
      children: [
        radio(SyncMethod.none, 'None'),
        radio(SyncMethod.git, 'Git Repository'),
        radio(SyncMethod.googleDrive, 'Google Drive'),
        radio(SyncMethod.customPath, 'Custom Path'),
      ],
    );
  }

  // ─── Git sync ─────────────────────────────────────────────────────────────

  Widget _buildGitSection(AppColorScheme colors) {
    return _SyncCard(
      children: [
        _SyncTextField(
          controller: _gitRemoteCtrl,
          label: 'Remote URL',
          hint: 'https://github.com/user/repo.git',
        ),
        const SizedBox(height: 10),
        _SyncTextField(
          controller: _gitBranchCtrl,
          label: 'Branch',
          hint: 'yoloit-sync',
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Switch(
              value: _autoPush,
              onChanged: (v) => setState(() => _autoPush = v),
              activeColor: colors.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'Auto-push on change',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () => _showComingSoon('Sync Now'),
          icon: const Icon(Icons.sync, size: 16),
          label: const Text('Sync Now'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            textStyle: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  // ─── Google Drive ─────────────────────────────────────────────────────────

  Widget _buildGDriveSection(AppColorScheme colors) {
    return _SyncCard(
      children: [
        Row(
          children: [
            FilledButton.icon(
              onPressed: () {
                _showComingSoon('Connect Google Account');
                setState(() => _gdriveConnected = !_gdriveConnected);
              },
              icon: Icon(
                _gdriveConnected ? Icons.check_circle : Icons.link,
                size: 16,
              ),
              label: Text(
                _gdriveConnected ? 'Connected' : 'Connect Google Account',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 12),
            _StatusIndicator(connected: _gdriveConnected),
          ],
        ),
        const SizedBox(height: 10),
        _SyncTextField(
          controller: _gdriveFolderCtrl,
          label: 'Sync Folder',
          hint: '/YoLoIT/sync',
        ),
      ],
    );
  }

  // ─── Custom path ──────────────────────────────────────────────────────────

  Widget _buildCustomPathSection(AppColorScheme colors) {
    return _SyncCard(
      children: [
        Row(
          children: [
            Expanded(
              child: _SyncTextField(
                controller: _customPathCtrl,
                label: 'Directory Path',
                hint: '/home/user/yoloit-sync',
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => _showComingSoon('Browse'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: const Text('Browse'),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Info expander ────────────────────────────────────────────────────────

  Widget _buildSyncInfoExpander(AppColorScheme colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.only(
            left: 14,
            right: 14,
            bottom: 12,
          ),
          title: Text(
            'What gets synced',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          iconColor:
              Theme.of(context).textTheme.bodySmall?.color ??
              Theme.of(context).colorScheme.onSurface,
          children: [
            _syncInfoRow(
              Icons.check_circle,
              'Board layouts and panel states',
              AppColors.neonGreen,
            ),
            _syncInfoRow(
              Icons.check_circle,
              'Settings and preferences',
              AppColors.neonGreen,
            ),
            _syncInfoRow(
              Icons.check_circle,
              'Skills configuration',
              AppColors.neonGreen,
            ),
            _syncInfoRow(Icons.cancel, 'Media files', AppColors.neonRed),
            _syncInfoRow(Icons.cancel, 'Terminal sessions', AppColors.neonRed),
          ],
        ),
      ),
    );
  }

  Widget _syncInfoRow(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared widgets ─────────────────────────────────────────────────────────

class _SyncCard extends StatelessWidget {
  const _SyncCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _SyncTextField extends StatelessWidget {
  const _SyncTextField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color:
                Theme.of(context).textTheme.bodySmall?.color ??
                Theme.of(context).colorScheme.onSurface,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(
              color:
                  Theme.of(context).textTheme.bodySmall?.color ??
                  Theme.of(context).colorScheme.onSurface,
              fontSize: 12,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.border),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.connected});
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final color = connected ? AppColors.neonGreen : AppColors.textMuted;
    final label = connected ? 'Connected' : 'Not connected';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
