import 'package:flutter/material.dart';
import 'package:yoloit/features/settings/data/widget_permissions_service.dart';

/// Settings section for allowing/denying JS API methods in widget/app panels.
class WidgetPermissionsSection extends StatefulWidget {
  const WidgetPermissionsSection({super.key});

  @override
  State<WidgetPermissionsSection> createState() =>
      _WidgetPermissionsSectionState();
}

class _WidgetPermissionsSectionState extends State<WidgetPermissionsSection> {
  final _service = WidgetPermissionsService.instance;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _service.load().then((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    if (!_loaded) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Control which JS APIs widget/app panels are allowed to use. '
          'Changes apply to newly loaded widgets.',
          style: TextStyle(fontSize: 12, color: muted),
        ),
        const SizedBox(height: 16),
        ...WidgetPermissionsService.permissions.map(
          (perm) => _PermRow(perm: perm, service: _service),
        ),
      ],
    );
  }
}

class _PermRow extends StatefulWidget {
  const _PermRow({required this.perm, required this.service});
  final WidgetPermission perm;
  final WidgetPermissionsService service;

  @override
  State<_PermRow> createState() => _PermRowState();
}

class _PermRowState extends State<_PermRow> {
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = widget.service.isAllowed(widget.perm.key);
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.perm.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.perm.description,
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ),
          Switch(
            value: _enabled,
            onChanged: (v) {
              setState(() => _enabled = v);
              widget.service.setAllowed(widget.perm.key, v);
            },
          ),
        ],
      ),
    );
  }
}
