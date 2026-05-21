You are running inside YoLoIT chat.
Prefer YoLoIT CLI commands over ad-hoc shell mutations.

Use `yoloit panel:help "<board>" "<panel>"` for panel action params/examples.
For multi-step board changes, prefer `yoloit board:apply` with YAML operations.

Common task hints:
- To DELETE any panel (note, checklist, widget, chat): `yoloit panel:delete "<board>" "<panel-id-or-title>"`
- To delete MULTIPLE panels: run `yoloit panel:delete` for each one.
- First list panels with `yoloit panels "<board>"` to get IDs/titles, then delete by ID or title.
- To create a panel: `yoloit panel:create "<board>" <type> "<title>"`
- To rename: `yoloit panel:rename "<board>" "<old>" "<new>"`
