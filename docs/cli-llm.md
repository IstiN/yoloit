# YoLoIT CLI
L:{📋=board;🪟=panel;B=⟨board⟩;P=⟨panel⟩;✓✓=required}

## Prereq
✓✓Flutter app running;✓✓`tools/yoloit`+x;PATH+=tools/
Port:~/.config/yoloit/cli.port

## 🖥️App
`reload`→hot reload|`restart`→hot restart

## 📋Board Cmds
```
boards→list        board B→detail
board:create|rename|delete|focus B [newname]
board:zoom B ⟨scale⟩     board:translate B ⟨x y⟩
board:fit B [WxH]        board:arrange B [→right|↓down] [hGap vGap]
board:apply B [file|-]→YAML bulk
board:snapshot B→YAML    board:screenshot B [.png]
board:svg B [.svg]
```

## 🪟Panel Cmds
```
panels B→list           panel B P→detail+content
panel:create B ⟨type⟩ ⟨title⟩    panel:types B
panel:rename B P ⟨name⟩
panel:move B P ⟨x y⟩    panel:resize B P ⟨w h⟩
panel:color B P ⟨#hex|clear⟩
panel:hide|show|delete|focus B P
do B P ⟨action⟩ [args...]→generic
```

## 🪟Types
|ID|📛|Size|
|---|---|---|
|board.note.markdown|📝|300×240|
|board.checklist|✅|280×360|
|board.kanban|📊|600×400|
|board.chat|💬|360×480|
|board.playlist|🎵|380×480|
|board.webpage|🌐|640×480|
|board.code.snippet|💻|400×300|
|board.files|📁|320×400|
|board.file.preview|🖼️|400×400|
|board.terminal|⌨️|480×320|
|board.filetree|🌳|320×500|
|board.run_configs|▶️|600×400|
|board.yolo_assistant|🤖|420×560|

## Shorthand
```
📝 note B P ⟨text⟩       note:append B P ⟨text⟩
   note:wrap|nowrap B P→auto-height ✓/✗

✅ checklist:add B P ⟨item⟩
   checklist:check|uncheck B P ⟨id⟩

📊 kanban:columns|cards B P
   kanban:add-column B P ⟨name⟩
   kanban:rename-column B P ⟨col⟩ ⟨name⟩
   kanban:remove-column B P ⟨col⟩
   kanban:add-card B P ⟨col⟩ ⟨title⟩
   kanban:update-card B P ⟨id⟩ ⟨title⟩
   kanban:move-card B P ⟨id⟩ ⟨col⟩
   kanban:remove-card B P ⟨id⟩

🎵 play B P ⟨file|url⟩
🌐 web:open B P ⟨url⟩
```

## 🔗Link Cmds
```
links B→list            link:create B ⟨from⟩ ⟨to⟩
link:delete B ⟨id⟩      link:style B ⟨id⟩ ⟨style⟩ [geom]
link:color B ⟨id⟩ ⟨#hex⟩
```
styles:`arrow|line`; geom:`bezier|straight|elbow`

## `do` Actions by Type

|Type|Actions|
|---|---|
|📝|`get\|set⟨text⟩\|append⟨text⟩\|wrap\|nowrap`|
|✅|`items\|add⟨text⟩\|check\|uncheck\|remove\|rename⟨id,[text]⟩`|
|📊|`columns\|cards\|add-column⟨name⟩\|rename-column⟨col,name⟩\|remove-column⟨col⟩`<br>`add-card⟨col,title,[desc],[color]⟩\|move-card⟨id,to⟩\|remove-card⟨id⟩\|update-card⟨id,[title],[desc],[color]⟩`|
|💬|`send⟨msg,[provider]⟩\|messages\|config⟨provider,[model]⟩\|clear`|
|🎵|`list\|add⟨path,[name]⟩\|remove⟨id⟩\|play[idx]\|pause\|stop\|next\|prev`|
|🌐|`open⟨url⟩\|get`|
|💻|`get\|set⟨code,[lang]⟩`|
|📁|`get\|open⟨path⟩`|
|⌨️|`config\|set-dir⟨path⟩`|
|🌳|`list[path]\|set-root⟨path⟩\|expand⟨path⟩\|collapse⟨path⟩\|open⟨path⟩\|refresh`|
|▶️|`list\|add⟨name,cmd,[dir]⟩\|remove⟨id⟩\|run⟨id⟩\|stop⟨id⟩\|output[id]\|config⟨id⟩`|
|🤖|`send⟨text⟩\|messages\|clear\|skills\|add-skill⟨s⟩\|remove-skill⟨s⟩\|mode⟨text\|voice⟩\|voice-start\|voice-stop`|

## YAML Bulk `board:apply`
```yaml
operations:
  - op: panel.create
    id: tmp; type: board.note.markdown
    title: Note; x: 120; y: 80; width: 320; height: 180
    state: {markdown: "# Hello"}
  - op: panel.update
    panel: tmp; color: "#8B5CF6"
  - op: link.create
    from: tmp; to: "other-panel"
  - op: board.fit
    viewportWidth: 1440; viewportHeight: 900
```
**ops:**
- `panel.{create|update|move|resize|delete|focus|color|hide|show|action}`
- `link.{create|delete|update}`
- `board.{focus|fit|zoom|translate|arrange}`

`id:`/`panelId:`→deterministic; `ref:`→reuse refs

## 🎨Colors
named:`red|green|blue|yellow|purple|pink|orange|teal|gray|white|clear`
hex:`#RRGGBB`|`#AARRGGBB`

## Examples

**Create project:**
```
b="Proj"; 📋:create→focus $b
🪟:create $b kanban "Sprint"
🪟:create $b note "README"
🪟:create $b chat "AI"
note $b "README" "# Proj"
kanban:add-column $b "Sprint" ×3→"Todo|In Progress|Done"
kanban:add-card $b "Sprint" "Todo" "Setup CI"
📋:fit $b
```

**Mind-map flow:**
```
🪟:create $b note ×3→"Step 1|2|3"
🔗:create $b "Step 1"→"Step 2"→"Step 3"
📋:arrange $b right→📋:fit $b
```
