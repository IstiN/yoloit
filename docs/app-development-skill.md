# YoLoIT App Development Skill

> **For AI agents**: This document is the authoritative guide for creating YoLoIT apps. Read it fully before writing any app code. Use `yoloit app:dev-skill` to print this from the CLI.

---

## What is a YoLoIT App?

A YoLoIT app is a self-contained mini-application that runs on the YoLoIT board as a panel. It consists of:
- **`widget.js`** — JavaScript code (ES5-compatible) that drives the UI and logic
- **`manifest.json`** — metadata (id, name, icon, permissions)

Apps run in a sandboxed JavaScript engine (JavaScriptCore on macOS/iOS). They communicate with Flutter via the `yoloit.*` API.

---

## Folder Structure

```
~/.config/yoloit/apps/
└── my-app/
    ├── manifest.json
    └── widget.js
```

---

## manifest.json

```json
{
  "id": "my-app",
  "name": "My App",
  "description": "Short description shown in the app picker",
  "version": "1.0.0",
  "icon": "🚀",
  "allowedCommands": [],
  "network": true
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `id` | ✅ | Unique identifier, kebab-case, matches folder name |
| `name` | ✅ | Display name shown in UI |
| `description` | ✅ | Short description |
| `version` | ✅ | Semver string |
| `icon` | ✅ | Emoji used in the app picker |
| `network` | ❌ | `true` to allow HTTP requests (default: false) |
| `allowedCommands` | ❌ | Reserved for future CLI command permissions |

---

## widget.js — Code Structure

Always wrap your app in an IIFE to avoid polluting the global scope:

```javascript
(function() {
  // Your app code here

  function render() {
    yoloit.render({ /* UI tree */ });
  }

  function handleEvent(actionId, payload) {
    // Handle button taps, textField submissions, etc.
  }

  yoloit.onEvent(handleEvent);
  render();
})();
```

---

## The `yoloit` API

### `yoloit.render(tree)`
Replaces the entire panel UI with a new widget tree (JSON).

```javascript
yoloit.render({
  type: 'column',
  children: [
    { type: 'text', data: 'Hello World' },
    { type: 'button', label: 'Click me', onPressed: 'btn_click' }
  ]
});
```

---

### `yoloit.onEvent(handler)`
Register a handler for all UI events (button taps, textField changes, etc.).

```javascript
yoloit.onEvent(function(actionId, payload) {
  if (actionId === 'btn_click') {
    // handle it
  }
});
```

`actionId` — string you put in `onTap`, `onPressed`, `onSubmit`, `onChange`  
`payload` — optional object with extra data (e.g. `{ value: 'text typed' }`)

---

### `yoloit.fetchJson(url, opts)` → Promise
HTTP fetch via Dart (bypasses CORS, uses native networking).

```javascript
yoloit.fetchJson('https://api.example.com/data', {
  method: 'GET',           // 'GET' | 'POST' | 'PUT' | 'DELETE'
  headers: { 'Authorization': 'Bearer token' }
}).then(function(data) {
  // data is already parsed JSON
  render(data);
}).catch(function(err) {
  yoloit.showError('Failed: ' + err);
});
```

Requires `"network": true` in manifest.json.

---

### `yoloit.storage` — Persistent Storage
Per-app persistent storage (survives hot reload, hot restart, app restarts). Plain JSON values.

```javascript
// Save a value
yoloit.storage.set('city', 'London');
yoloit.storage.set('settings', { theme: 'dark', count: 42 });

// Read a value (returns a Promise)
yoloit.storage.get('city').then(function(city) {
  if (city) render(city);
});

// Delete a value
yoloit.storage.delete('city');
```

---

### `yoloit.secrets` — Secure Storage
Per-app encrypted secure storage (uses platform Keychain/Keystore). For API keys, tokens, passwords.

```javascript
// Save a secret
yoloit.secrets.set('api_key', 'sk-abc123');

// Read a secret (returns a Promise)
yoloit.secrets.get('api_key').then(function(key) {
  if (key) makeApiCall(key);
});

// Delete a secret
yoloit.secrets.delete('api_key');
```

---

### `yoloit.theme` — Current Theme Colors
Reactive theme object. Always use these colors instead of hardcoded hex values so your app respects light/dark mode.

```javascript
var t = yoloit.theme;
// t.isDark   — boolean
// t.bg       — main background color hex (e.g. '#0f172a')
// t.surface  — card/panel surface color
// t.border   — border color
// t.accent   — accent/primary color
// t.text     — primary text color
// t.muted    — secondary/muted text color
```

---

### `yoloit.onThemeChange(callback)`
Subscribe to theme changes (when user toggles dark/light mode).

```javascript
yoloit.onThemeChange(function(theme) {
  // theme has same fields as yoloit.theme
  render(); // re-render with new colors
});
```

---

### `yoloit.panel.setTitle(title)`
Update the panel header title.

```javascript
yoloit.panel.setTitle('Weather — London');
```

---

### `yoloit.showError(message)`
Display an error overlay in the panel.

```javascript
yoloit.showError('Failed to load data');
```

---

### `console.log / console.warn / console.error`
Standard console logging — output visible in Flutter debug console.

```javascript
console.log('Loading data for', city);
console.error('Something went wrong:', err);
```

---

### `setTimeout / setInterval / clearTimeout / clearInterval`
Standard timer functions.

```javascript
var timer = setInterval(function() {
  refresh();
}, 30000); // every 30 seconds

// Stop it:
clearInterval(timer);
```

---

## UI Node Types (Widget Tree)

All nodes are plain JSON objects with a `type` field.

### Layout

| Type | Key props | Description |
|------|-----------|-------------|
| `column` | `children`, `mainAxisAlignment`, `crossAxisAlignment`, `mainAxisSize` | Vertical stack |
| `row` | `children`, `mainAxisAlignment`, `crossAxisAlignment` | Horizontal stack |
| `stack` | `children`, `alignment` | Overlapping layers |
| `center` | `child` | Center child |
| `padding` | `child`, `padding: [left, top, right, bottom]` | Add padding |
| `expanded` | `child`, `flex` | Flex expand inside row/column |
| `sizedBox` | `width`, `height`, `child` | Fixed size box |
| `safeArea` | `child` | Insets for notches/bars |
| `aspectRatio` | `child`, `aspectRatio` | Force aspect ratio |
| `listView` | `children`, `shrinkWrap`, `scrollDirection` | Scrollable list |

### Display

| Type | Key props | Description |
|------|-----------|-------------|
| `text` | `data`, `style` | Text label |
| `icon` | `name`, `color`, `size` | Material icon by name |
| `divider` | `color`, `height`, `thickness` | Horizontal line |
| `image` | `url` or `asset`, `fit`, `width`, `height` | Image |

### Containers

| Type | Key props | Description |
|------|-----------|-------------|
| `container` | `child`, `color`, `decoration`, `padding`, `margin`, `width`, `height`, `alignment` | Styled box |
| `card` | `child`, `color`, `elevation`, `borderRadius` | Material card |
| `inkWell` | `child`, `onTap`, `borderRadius` | Tappable area (ripple effect) |

### Interactive

| Type | Key props | Description |
|------|-----------|-------------|
| `button` | `label`, `onPressed`, `icon`, `color`, `textColor` | Elevated button |
| `textField` | `hint`, `value`, `onSubmit`, `onChange`, `obscure` | Text input field |

### Data Viz

| Type | Key props | Description |
|------|-----------|-------------|
| `chart` | `data`, `color`, `fillColor`, `strokeWidth`, `height` | Sparkline chart (line graph) |

---

## Node Reference — Key Props

### `text`
```javascript
{
  type: 'text',
  data: 'Hello',
  style: {
    color: '#ffffff',
    fontSize: 14,
    fontWeight: 'w600',    // w100–w900, bold, normal
    fontStyle: 'italic',
    textAlign: 'center',   // left, center, right, justify
    letterSpacing: 1.2,
  },
  maxLines: 1,
  overflow: 'ellipsis',   // ellipsis, clip, fade, visible
}
```

### `container`
```javascript
{
  type: 'container',
  width: 200,
  height: 100,
  padding: [16, 8, 16, 8],    // [left, top, right, bottom]
  margin: [0, 4, 0, 4],
  alignment: 'center',         // center, topLeft, bottomRight, etc.
  decoration: {
    color: '#1e293b',
    borderRadius: 12,          // number OR [tl, tr, br, bl]
    border: { color: '#334155', width: 1 },
    gradient: {
      type: 'linear',          // linear | radial
      colors: ['#1e293b', '#0f172a'],
    },
  },
  child: { type: 'text', data: 'hi' },
}
```

### `inkWell`
```javascript
{
  type: 'inkWell',
  onTap: 'my_action',          // fires handleEvent('my_action', {})
  borderRadius: 8,
  child: { type: 'text', data: 'Tap me' },
}
```

### `button`
```javascript
{
  type: 'button',
  label: 'Submit',
  onPressed: 'btn_submit',     // fires handleEvent('btn_submit', {})
  icon: 'send',                // optional Material icon name
  color: '#2563eb',
  textColor: '#ffffff',
}
```

### `textField`
```javascript
{
  type: 'textField',
  hint: 'Enter city...',
  value: currentCity,          // pre-fill
  onSubmit: 'city_submit',     // fires handleEvent('city_submit', { value: 'London' })
  onChange: 'city_change',     // fires on every keystroke
  obscure: false,              // true for passwords
}
```

### `chart`
```javascript
{
  type: 'chart',
  data: [1.2, 2.5, 1.8, 3.0, 2.1],   // array of numbers
  color: '#22c55e',                    // line color
  fillColor: '#22c55e33',             // fill under line (semi-transparent)
  strokeWidth: 2,
  height: 60,
}
```

### `icon`
```javascript
{
  type: 'icon',
  name: 'settings',     // Material icon name (snake_case)
  color: '#94a3b8',
  size: 24,
}
```

---

## MainAxisAlignment / CrossAxisAlignment Values

```
mainAxisAlignment: 'start' | 'end' | 'center' | 'spaceBetween' | 'spaceAround' | 'spaceEvenly'
crossAxisAlignment: 'start' | 'end' | 'center' | 'stretch' | 'baseline'
mainAxisSize: 'max' | 'min'
```

---

## Full Example: Hello World

```javascript
(function() {
  var count = 0;
  var t = yoloit.theme;

  function render() {
    yoloit.render({
      type: 'center',
      child: {
        type: 'column',
        mainAxisSize: 'min',
        children: [
          {
            type: 'text',
            data: 'Count: ' + count,
            style: { color: t.text, fontSize: 32, fontWeight: 'bold' }
          },
          { type: 'sizedBox', height: 16 },
          {
            type: 'button',
            label: 'Tap me!',
            onPressed: 'increment',
            color: t.accent
          }
        ]
      }
    });
  }

  yoloit.onEvent(function(actionId) {
    if (actionId === 'increment') {
      count++;
      yoloit.storage.set('count', count);
      render();
    }
  });

  yoloit.onThemeChange(function(theme) {
    t = theme;
    render();
  });

  yoloit.panel.setTitle('Counter');

  // Restore saved count
  yoloit.storage.get('count').then(function(saved) {
    if (saved !== null) count = saved;
    render();
  });
})();
```

---

## Full Example: HTTP Fetch

```javascript
(function() {
  var data = null;
  var loading = true;

  function render() {
    var t = yoloit.theme;
    if (loading) {
      yoloit.render({
        type: 'center',
        child: { type: 'text', data: 'Loading...', style: { color: t.muted } }
      });
      return;
    }
    yoloit.render({
      type: 'padding',
      padding: [16, 16, 16, 16],
      child: {
        type: 'column',
        children: data.map(function(item) {
          return {
            type: 'text',
            data: item.name,
            style: { color: t.text, fontSize: 14 }
          };
        })
      }
    });
  }

  function load() {
    loading = true;
    render();
    yoloit.fetchJson('https://jsonplaceholder.typicode.com/users')
      .then(function(users) {
        data = users;
        loading = false;
        render();
      })
      .catch(function(err) {
        yoloit.showError('Error: ' + err);
        loading = false;
        render();
      });
  }

  yoloit.onEvent(function(actionId) {
    if (actionId === 'refresh') load();
  });

  yoloit.panel.setTitle('Users');
  load();
})();
```

---

## CLI Workflow for App Development

```bash
# 1. Scaffold a new app
yoloit app:create my-app

# 2. Edit the generated files
#    ~/.config/yoloit/apps/my-app/widget.js
#    ~/.config/yoloit/apps/my-app/manifest.json

# 3. Open it on the board
yoloit app:run my-app

# 4. After editing widget.js, hot-reload without restarting
yoloit app:reload my-app

# 5. Trigger an event manually for testing
yoloit app:execute my-app btn_click

# 6. Inspect the current render tree (JSON)
yoloit app:snapshot my-app

# 7. List all installed apps
yoloit app:list

# 8. Install from a path or URL
yoloit app:install ~/projects/my-app
yoloit app:install https://example.com/my-app.js

# 9. Remove an app
yoloit app:remove my-app
```

---

## Tips for AI Agents

1. **Always use `yoloit.theme` colors** — never hardcode hex values. Users switch between light and dark mode.
2. **Wrap everything in IIFE** — `(function(){ ... })()` — functions inside are NOT global.
3. **`yoloit.onEvent` is mandatory** — register it even if you handle few events; the engine uses `yoloit._handler`.
4. **Storage is async** — `yoloit.storage.get()` returns a Promise. Always `.then()` before using the value.
5. **`yoloit.render()` replaces everything** — it's not additive; always render the complete UI tree.
6. **Hot reload** — after editing `widget.js`, run `yoloit app:reload <id>`. No need to restart the Flutter app.
7. **Network requires manifest** — set `"network": true` in `manifest.json` or `fetchJson` will fail silently.
8. **Timer cleanup** — if you use `setInterval`, save the ID and `clearInterval` when needed to avoid memory leaks.
9. **`app:snapshot`** — use this to debug the render tree when the UI looks wrong.
10. **`app:execute`** — use this to fire events from tests or the CLI to validate app logic.
