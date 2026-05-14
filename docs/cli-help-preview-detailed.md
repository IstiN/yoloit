# CLI Help Preview (detailed)

```text
yoloit help (detailed)

Command: reload
Description: Hot reload the running Flutter app
CLI command format: yoloit reload
Example: yoloit reload

Command: restart
Description: Hot restart the running Flutter app
CLI command format: yoloit restart
Example: yoloit restart

Command: boards
Description: List all boards
CLI command format: yoloit boards
Example: yoloit boards

Command: board
Description: Show board details
Parameters:
  - id|name (required): Board identifier or board name
CLI command format: yoloit board <id|name>
Example: yoloit board "My Board"

Command: board:create
Description: Create a new board
Parameters:
  - name (required): New board name
CLI command format: yoloit board:create <name>
Example: yoloit board:create "My Board"

Command: board:snapshot
Description: Text snapshot of board layout
Parameters:
  - id|name (required): Board identifier or board name
  - --format md|mermaid (optional): Output format (default: md)
CLI command format: yoloit board:snapshot <id|name> [--format md|mermaid]
Example: yoloit board:snapshot "My Board" --format mermaid

Command: board:diagram
Description: Alias for board snapshot focused on diagram output
Parameters:
  - id|name (required): Board identifier or board name
  - --format mermaid|md (optional): Output format (default: mermaid)
CLI command format: yoloit board:diagram <id|name> [--format mermaid|md]
Example: yoloit board:diagram "My Board" --format mermaid

Command: board:screenshot
Description: Save PNG screenshot
Parameters:
  - id|name (required): Board identifier or board name
  - file.png (optional): Output PNG path
CLI command format: yoloit board:screenshot <id|name> [file.png]
Example: yoloit board:screenshot "My Board" out.png

Command: board:svg
Description: Export SVG layout
Parameters:
  - id|name (required): Board identifier or board name
  - file.svg (optional): Output SVG path
CLI command format: yoloit board:svg <id|name> [file.svg]
Example: yoloit board:svg "My Board" layout.svg

Command: board:apply
Description: Apply YAML bulk operations from file or stdin
Parameters:
  - id|name (required): Board identifier or board name
  - file|- (optional): YAML file path or '-' for stdin
CLI command format: yoloit board:apply <id|name> [file|-]
Example: yoloit board:apply "My Board" flow.yaml

Command: panels
Description: List panels on board
Parameters:
  - board (required): Board id or name
CLI command format: yoloit panels <board>
Example: yoloit panels "My Board"

Command: panel
Description: Show panel details and content
Parameters:
  - board (required): Board id or name
  - panel (required): Panel id or title
CLI command format: yoloit panel <board> <panel>
Example: yoloit panel "My Board" "Run"

Command: panel:help
Description: Show dynamic panel actions with parameter docs
Parameters:
  - board (required): Board id or name
  - panel (required): Panel id or title
CLI command format: yoloit panel:help <board> <panel>
Example: yoloit panel:help "My Board" "Run"

Command: do
Description: Execute panel action
Parameters:
  - board (required): Board id or name
  - panel (required): Panel id or title
  - action (required): Action name from panel:help
  - json (optional): JSON body (optional)
CLI command format: yoloit do <board> <panel> <action> [json]
Example: yoloit do "My Board" "Run" list

Command: run:list
Description: List run configurations and sessions
Parameters:
  - board (required): Board id or name
  - panel (required): Run panel id or title
CLI command format: yoloit run:list <board> <panel>
Example: yoloit run:list "My Board" "Run"

Command: run:input
Description: Send stdin to running run session
Parameters:
  - board (required): Board id or name
  - panel (required): Run panel id or title
  - sessionId|id|name (required): Session or config selector
  - text (required): Input text
  - --enter (optional): Append newline
CLI command format: yoloit run:input <board> <panel> <sessionId|id|name> <text> [--enter]
Example: yoloit run:input "My Board" "Run" preset_flutter_run_macos r

Command: run:attach
Description: Attach run console to matching session
Parameters:
  - board (required): Board id or name
  - panel (required): Run panel id or title
  - sessionId|id|name (optional): Session or config selector
  - --any (optional): Allow stopped sessions
CLI command format: yoloit run:attach <board> <panel> [sessionId|id|name] [--any]
Example: yoloit run:attach "My Board" "Run" --any

Command: run:popout
Description: Open detached session in a new Run panel
Parameters:
  - board (required): Board id or name
  - panel (required): Run panel id or title
  - sessionId|id|name (optional): Session or config selector
CLI command format: yoloit run:popout <board> <panel> [sessionId|id|name]
Example: yoloit run:popout "My Board" "Run"

Command: links
Description: List links on board
Parameters:
  - board (required): Board id or name
CLI command format: yoloit links <board>
Example: yoloit links "My Board"

Command: link:create
Description: Create panel link
Parameters:
  - board (required): Board id or name
  - from (required): Source panel
  - to (required): Target panel
CLI command format: yoloit link:create <board> <from> <to>
Example: yoloit link:create "My Board" "A" "B"

```
