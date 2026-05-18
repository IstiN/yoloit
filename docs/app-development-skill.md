# YoLoIT App Development Skill

> **For AI agents**: This is the authoritative guide for creating YoLoIT apps. Use `yoloit app:dev-skill` to print this. Read the **Quick Start** first — it shows the minimal workflow.

---

## ⚡ Quick Start (Minimal Workflow for AI Agents)

### Option A — Local dev (Recommended for AI agents)
Develop in your current working directory. No copy, no install. The app loads directly from disk.

```bash
# Step 1: Create app folder in working directory
mkdir my-app && cd my-app

# Step 2: Write manifest.json
# ⚠️  NEVER use heredoc (cat << 'EOF') — it hangs in AI agent bash sessions.
# Use printf or python3 to write files:
printf '{"id":"my-app","name":"My App","description":"...","version":"1.0.0","icon":"🔧","network":false}\n' > manifest.json
# or:
python3 -c "open('manifest.json','w').write('{\"id\":\"my-app\",\"name\":\"My App\",\"description\":\"...\",\"version\":\"1.0.0\",\"icon\":\"🔧\",\"network\":false}')"

# Step 3: Write widget.js (see API below — use printf or python3, NOT heredoc)
# ... edit widget.js ...

# Step 4: Open from local path — board and panel are auto-selected/created
yoloit app:run .

# Step 5: After each edit, hot-reload (no restart needed)
yoloit app:reload .

# Step 6: See console.log output
yoloit app:logs .

# Step 7: Inspect render tree to debug UI
yoloit app:snapshot .

# Step 8: Fire events manually to test logic
yoloit app:execute . btn_click
```

**All app commands accept `.` (current dir), `./subdir`, or any absolute path — board and panel are always optional (auto-resolved).**

### Option B — Scaffold into apps folder (for permanent apps)
```bash
yoloit app:create my-app     # creates ~/.config/yoloit/apps/my-app/
# edit ~/.config/yoloit/apps/my-app/widget.js
yoloit app:run my-app        # open by id
yoloit app:reload my-app     # hot-reload by id
```

### Option C — Install from path (copy into apps folder)
```bash
yoloit app:install .         # installs current dir as permanent app
yoloit app:install ./my-app  # installs ./my-app folder
yoloit app:run <id>          # run by manifest id
```

### ⚠️ Critical Rules for AI Agents

1. **NEVER use heredoc (`cat << 'EOF'`)** — it hangs in AI agent bash sessions. Use `printf` or `python3 -c "open('file','w').write(...)"` to write files.
2. **NEVER use `app:install` for local dev** — use `app:run .` directly. `app:install` copies to apps folder (use only for distributing finished apps).
3. **After editing `widget.js` → always call `app:reload .`** — hot-reloads without restart.
4. **Board and panel are always optional** — `app:run .` picks active board automatically.
5. **Check `app:logs .`** to see `console.log` output — essential for debugging.
6. **If `app:run .` fails** — check `yoloit boards` to verify YoLoIT is running.
7. **Read demo apps first** — run `app:demo` to list examples, then `app:demo-view <id>` to study patterns.

### Complete AI Agent Dev Workflow

```
1. mkdir my-app && cd my-app    create local app folder
2. write manifest.json + widget.js
3. yoloit app:run .             open panel (board auto-selected)
4. yoloit app:logs .            check console.log output
5. [edit widget.js]
6. yoloit app:reload .          hot-reload changes
7. yoloit app:snapshot .        inspect UI render tree
8. yoloit app:execute . <evt>   fire event manually for testing
```

### 🔧 Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `app:run .` fails silently | YoLoIT not running | Start YoLoIT app |
| `app:logs .` empty | No console.log called yet | Add `console.log('test')` to widget.js |
| UI not updating after reload | JS syntax error | Check `app:logs .` for error message |
| `yoloit.render()` not showing | Missing IIFE wrapper | Wrap all code in `(function(){ ... })()` |
| Button not working | Missing `yoloit.onEvent` | Always register `yoloit.onEvent(function(id){ ... })` |
| bash hangs when writing files | Using heredoc `cat << 'EOF'` | Use `printf '...' > file` or `python3 -c "open(...).write(...)"` |

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
| `files` | ❌ | Ordered list of JS files to concatenate before evaluation (multi-file apps) |

---

## Multi-File Apps

Large apps can be split into multiple JS files. Use the `files` array in `manifest.json` to specify the load order:

```json
{
  "id": "my-app",
  "name": "My App",
  "version": "1.0.0",
  "icon": "🚀",
  "files": ["lib/utils.js", "lib/api.js", "widget.js"]
}
```

All files are concatenated in order and evaluated as a single script. Single-file apps (no `files` field) continue to work unchanged.

### `yoloit.include('path')` — Static Inlining

You can also inline files inside any JS file using `yoloit.include('relative/path')`. This is a **preprocessor** directive — it is replaced with the file's contents before the JS engine sees the code:

```javascript
// lib/utils.js
yoloit.include('lib/helpers.js');   // inlined before eval

function formatDate(ts) { /* ... */ }
```

- Paths are relative to the app's folder
- Supports subdirectories: `yoloit.include('lib/api/client.js')`
- Maximum recursion depth: 5 levels
- If the file is not found, replaced with a comment (no crash)

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

### `yoloit.loadAsset(path)` → Promise\<string|null\>
Reads a file from the app's folder and returns its text content as a string. Returns `null` if the file is not found.

```javascript
yoloit.loadAsset('logo.svg').then(function(svgText) {
  if (svgText) {
    // use svgText
  }
});

// Supports subdirectories
yoloit.loadAsset('assets/config.json').then(function(json) {
  var config = JSON.parse(json);
});
```

This is useful for loading SVGs, JSON config files, templates, or any static asset bundled with the app.

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

## CLI Reference for App Development

```bash
# ── Creating ──────────────────────────────────────────────────────────────────

# Create a new app (scaffold in ~/.config/yoloit/apps/<name>/)
yoloit app:create my-app
yoloit app:create my-app --template network   # with HTTP fetch example
yoloit app:create my-app --template yoloit    # with storage + theme example

# ── Running ───────────────────────────────────────────────────────────────────

# Open app as a panel on the board
yoloit app:run my-app

# Hot-reload JS after editing widget.js (no Flutter restart needed)
yoloit app:reload my-app

# ── Debugging ─────────────────────────────────────────────────────────────────

# Inspect the current JSON render tree
yoloit app:snapshot my-app

# Fire an event manually (simulate button tap, etc.)
yoloit app:execute my-app btn_click
yoloit app:execute my-app city_submit '{"value":"London"}'

# ── Managing ──────────────────────────────────────────────────────────────────

# List all discovered apps and which are active
yoloit app:list

# Install from EXTERNAL sources (NOT needed for apps you created with app:create)
yoloit app:install ~/projects/external-app     # from path outside apps folder
yoloit app:install https://example.com/app.js  # from URL
yoloit app:install ~/downloads/my-app.zip      # from ZIP archive

# Remove an app
yoloit app:remove my-app
```

**Important**: `app:install` is only needed for apps from OUTSIDE `~/.config/yoloit/apps/`.  
Apps created with `app:create` or manually placed in `~/.config/yoloit/apps/` are **automatically discovered** — just `app:run` them directly.

---

## Built-in Demo Apps

Real-world examples you can study and run. Use these as starting points for your own apps.

```bash
# List all demo apps with their local paths
yoloit app:demo

# Read the full source of a demo app (manifest.json + widget.js)
yoloit app:demo-view calculator
yoloit app:demo-view weather
yoloit app:demo-view crypto
yoloit app:demo-view stocks

# Run a demo app on the board
yoloit app:run calculator
```

| ID | Name | Description | Network |
|----|------|-------------|---------|
| `calculator` | Calculator | Scientific calculator — pure JS, no network | ❌ |
| `weather` | Weather | Current weather via wttr.in API, city input with storage | ✅ |
| `crypto` | Crypto Prices | Live BTC/ETH/SOL via CoinGecko, auto-refresh | ✅ |
| `stocks` | Stock Prices | Real-time stock quotes, textField + fetch | ✅ |

**Tip**: Before building a new app, always run `app:demo-view <similar-app>` to study the pattern — especially for network fetch, storage, and theming.

---

## Tips for AI Agents

1. **Always use `yoloit.theme` colors** — never hardcode hex. Users switch dark/light mode.
2. **Wrap everything in an IIFE** — `(function(){ ... })()` — functions inside are NOT global.
3. **`yoloit.onEvent` is mandatory** — register it even if you handle few events; the engine uses `yoloit._handler`.
4. **Storage is async** — `yoloit.storage.get()` returns a Promise. Always use `.then()` before using the value.
5. **`yoloit.render()` replaces everything** — not additive; always render the complete UI tree.
6. **After editing `widget.js` → `yoloit app:reload .`** — no Flutter restart needed.
7. **Network requires manifest flag** — set `"network": true` or `fetchJson` silently fails.
8. **Timer cleanup** — save `setInterval` IDs and `clearInterval` when done.
9. **Use `app:snapshot .`** — inspect the render tree when UI looks wrong.
10. **Use `app:logs .`** — see `console.log` output; use it liberally for debugging.
11. **Use `app:execute . <evt>`** — fire events from CLI to test app logic without clicking.
12. **`app:run .` is idempotent** — safe to call even if the panel already exists.
13. **NEVER call `app:install .`** during development — use `app:run .` directly from your working directory.
14. **NEVER use heredoc** (`cat << 'EOF'`) — hangs in AI bash sessions. Use `printf '...' > file` or `python3 -c "open('f','w').write('...')"`.
15. **Study demo apps first** — `app:demo` lists them, `app:demo-view <id>` shows full source.
