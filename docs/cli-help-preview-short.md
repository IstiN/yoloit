# CLI Help Preview (short)

```text
yoloit help (short)
Use: yoloit help --format [short|detailed|mermaid|tools]

app:
  reload — Hot reload the running Flutter app
    ex: yoloit reload
  restart — Hot restart the running Flutter app
    ex: yoloit restart

board:
  boards — List all boards
    ex: yoloit boards
  board — Show board details
    params: id|name*
    ex: yoloit board "My Board"
  board:create — Create a new board
    params: name*
    ex: yoloit board:create "My Board"
  board:snapshot — Text snapshot of board layout
    params: id|name*, --format md|mermaid
    ex: yoloit board:snapshot "My Board" --format mermaid
  board:diagram — Alias for board snapshot focused on diagram output
    params: id|name*, --format mermaid|md
    ex: yoloit board:diagram "My Board" --format mermaid
  board:screenshot — Save PNG screenshot
    params: id|name*, file.png
    ex: yoloit board:screenshot "My Board" out.png
  board:svg — Export SVG layout
    params: id|name*, file.svg
    ex: yoloit board:svg "My Board" layout.svg
  board:apply — Apply YAML bulk operations from file or stdin
    params: id|name*, file|-
    ex: yoloit board:apply "My Board" flow.yaml

panel:
  panels — List panels on board
    params: board*
    ex: yoloit panels "My Board"
  panel — Show panel details and content
    params: board*, panel*
    ex: yoloit panel "My Board" "Run"
  panel:help — Show dynamic panel actions with parameter docs
    params: board*, panel*
    ex: yoloit panel:help "My Board" "Run"
  do — Execute panel action
    params: board*, panel*, action*, json
    ex: yoloit do "My Board" "Run" list

run:
  run:list — List run configurations and sessions
    params: board*, panel*
    ex: yoloit run:list "My Board" "Run"
  run:input — Send stdin to running run session
    params: board*, panel*, sessionId|id|name*, text*, --enter
    ex: yoloit run:input "My Board" "Run" preset_flutter_run_macos r
  run:attach — Attach run console to matching session
    params: board*, panel*, sessionId|id|name, --any
    ex: yoloit run:attach "My Board" "Run" --any
  run:popout — Open detached session in a new Run panel
    params: board*, panel*, sessionId|id|name
    ex: yoloit run:popout "My Board" "Run"

link:
  links — List links on board
    params: board*
    ex: yoloit links "My Board"
  link:create — Create panel link
    params: board*, from*, to*
    ex: yoloit link:create "My Board" "A" "B"
```
