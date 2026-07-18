# js_widget_runtime — Writing JavaScript Widgets

`js_widget_runtime` is the shared package that lets you write small JavaScript
widgets that render as Flutter UI inside YoLoIT (or any other Flutter app that
imports the package).

A widget is just:

* a `manifest.json` with metadata, and
* a `widget.js` entry file that calls `jsr.render(tree)` whenever its UI
  should change.

The package is hosted at
`https://github.com/IstiN/flutter_js_widget_runtime` and published on pub.dev as
`js_widget_runtime`.

---

## 1. Minimal widget

Create a directory, e.g. `~/.config/yoloit/apps/hello/`:

**manifest.json**

```json
{
  "id": "hello",
  "name": "Hello Widget",
  "description": "A tiny demo widget",
  "version": "1.0.0",
  "icon": "👋"
}
```

**widget.js**

```js
var name = jsr.storage.get('name') || 'World';

function render() {
  jsr.render({
    type: 'column',
    mainAxisAlignment: 'center',
    crossAxisAlignment: 'center',
    children: [
      { type: 'text', data: 'Hello, ' + name + '!', style: { fontSize: 24 } },
      { type: 'sizedBox', height: 16 },
      {
        type: 'textField',
        hint: 'Your name',
        value: name,
        id: 'nameInput',
      },
      {
        type: 'button',
        label: 'Greet',
        onTap: 'greet',
      },
    ],
  });
}

function handleEvent(actionId, payload) {
  if (actionId === 'greet') {
    var live = jsr.storage.get('nameInput');
    name = live || payload.value || name;
    jsr.storage.set('name', name);
    render();
  }
}

render();
```

Load it in YoLoIT:

```bash
yoloit app:run ~/.config/yoloit/apps/hello
```

Or create a `board.widget.custom` panel and pick the widget from the catalog.

---

## 2. JavaScript API

The runtime injects a global `jsr` object.

### Rendering

```js
jsr.render(tree); // tree is a JSON widget tree (see section 3)
```

### Persistent per-panel storage

```js
jsr.storage.get(key);           // returns value or undefined
jsr.storage.set(key, value);    // value must be JSON-serialisable
```

Storage is automatically restored when the widget restarts.

### Theme

```js
var t = jsr.theme; // { isDark, bg, surface, border, accent, text, muted }
```

The runtime pushes a new `theme` object and calls `jsr._onThemeChange` when
the host theme changes. You can listen to it:

```js
jsr._onThemeChange = function(theme) { render(); };
```

### Network

```js
var result = await jsr.fetchJson(url, { method: 'GET', headers: {} });
// result is the parsed JSON, or { __error: '...' } on failure
```

Fetch requires the `fetch` permission to be enabled in Settings → Apps & Widgets.

### Running CLI commands

```js
var out = await jsr.exec('yoloit board:list');
// out = { stdout, stderr, exitCode }
```

Exec requires the `exec` permission.

### Secure secrets

```js
await jsr.secrets.set('apiKey', 'abc123');
var key = await jsr.secrets.get('apiKey');
```

### Loading local assets

```js
var svg = await jsr.loadAsset('assets/icon.svg');
```

Assets are resolved relative to the widget's directory.

### Panel title

```js
jsr.setTitle('Weather in Berlin');
```

### Errors

```js
jsr.showError('Could not load forecast');
```

### Timers / animation frames

```js
var id = setInterval(fn, 1000);
clearInterval(id);

var id2 = setTimeout(fn, 500);
clearTimeout(id2);

requestAnimationFrame(function(elapsedMs) { ... });
```

---

## 3. JSON widget tree reference

Every node has a `type`. Common nodes:

| Type | Notes |
|------|-------|
| `column`, `row`, `stack`, `wrap` | Layout nodes; use `children` |
| `center`, `align`, `padding`, `sizedBox`, `expanded`, `flexible`, `spacer` | Layout helpers |
| `text` | `data` or `text`; `style: { color, fontSize, fontWeight, textAlign }` |
| `icon` | `name` can be a Material icon name or emoji |
| `button`, `textButton`, `outlinedButton`, `iconButton` | `onTap` action id, `label`/`icon` |
| `textField` | `id`/`storageKey` auto-syncs to storage; `onChange`, `onSubmit` |
| `switch`, `checkbox`, `slider`, `dropdown` | Bind with `onChange` |
| `container`, `card`, `inkWell` | `decoration: { color, borderRadius, borderColor, borderWidth }` |
| `image` | `url` |
| `svg` | `data` (full SVG) or `path` (bare path d attribute) |
| `markdown` | `data` |
| `divider`, `circularProgressIndicator`, `linearProgressIndicator` | Display widgets |
| `listView`, `gridView`, `listTile` | Lists |
| `scroll` | Wraps a single child in a scroll view |
| `badge`, `chip`, `circleAvatar` | Material widgets |
| `animatedContainer`, `animatedOpacity`, `animatedPositioned` | Implicit animations |
| `path` | `path` (SVG path data), `progress`, `color`, `strokeWidth`, `cap`, `join` |
| `absoluteFill` / `fill` | Expands to fill parent; `color`, `child` |
| `video` | `src`, `autoPlay`, `loop`, `controls`, `fit`, `width`, `height` |
| `audio` | `src`, `autoPlay`, `loop`, `title` |

Colors can be hex strings (`#1e293b`) or named colors (`white`, `red`, ...).

### Universal effect props

Every node accepts: `offsetX`, `offsetY`, `scale`, `rotation` (radians), `opacity`, `blur`.

### Image sources

`image` supports `url`, `asset:<path>`, `file:<path>` and `external:<id>` references.

---

## 4. Local development workflow

Inside YoLoIT you can iterate without reinstalling:

```bash
# open / reload / stream logs
yoloit app:run   /path/to/widget
yoloit app:reload /path/to/widget
yoloit app:logs   /path/to/widget
```

The widget files do **not** need to be inside `~/.config/yoloit/apps/` while you
develop; the CLI mounts the directory directly.

---

## 5. Using the package in another Flutter app

Add to `pubspec.yaml`:

```yaml
dependencies:
  js_widget_runtime: ^0.3.0
```

Then:

```dart
import 'package:js_widget_runtime/js_widget_runtime.dart';

// Render a widget tree produced by JS
JsonWidgetRenderer(
  theme: JsonWidgetTheme.fromAccent(Colors.indigo),
  onEvent: (actionId, payload) { ... },
).build(tree, context);
```

To run a full JS widget from a directory:

```dart
final manifest = await WidgetManifest.fromStorage(
  widgetDir,
  reader: VmWidgetFileReader.instance,
);
final js = await manifest.readJs(reader: reader);
final engine = JsWidgetEngine(
  config: JsRuntimeConfig(
    widgetId: manifest.id,
    appDir: manifest.appDir,
    onRender: (tree) { ... },
    onSetTitle: (title) { ... },
    onStorageUpdate: (storage) { ... },
  ),
);
await engine.run(js);
```

---

## 6. Tips

* Keep widgets small and declarative. Store state in `jsr.storage`, not in
  closure variables, if you want it to survive reload.
* Use `handleEvent(actionId, payload)` as the single entry point for user
  actions; the JSON tree's `onTap` fields reference `actionId`s.
* Prefer `jsr.fetchJson` over `fetch` — it is proxied through Dart and works
  without CORS inside the desktop app.
* For expensive work, `await` inside `handleEvent`; the runtime waits for async
  handlers before considering the event done.
