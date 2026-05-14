# YoLoIT CLI Help Preview (Compact + Descriptions)

Compact tree used for first-message CLI guidance with short descriptions.

```text
yoloit
  board commands:
    boards — List all boards
    board <id|name> — Show board details
    board:
      create <name> — Create a new board
      rename <id|name> <new> — Rename a board
      delete <id|name> — Delete a board
      focus <id|name> — Switch to board
      snapshot <id|name> — Markdown snapshot of board layout
      screenshot <id|name> [file.png] — Save PNG screenshot
      svg <id|name> [file.svg] — Export SVG layout
      zoom <id|name> <scale> — Set viewport zoom
      fit <id|name> [WxH] — Auto-fit viewport to show all panels
      arrange <id|name> [right|down] [hSpacing] [vSpacing] — Auto-layout panels as tree
      apply <id|name> [file|-] — Apply YAML bulk operations from file or stdin

  app commands:
    reload — Hot reload the running Flutter app
    restart — Hot restart the running Flutter app

  panel commands:
    panels <board> — List panels on a board
    panel <board> <panel> — Show panel details & content
    panel:
      help <board> <panel> — Show supported actions with parameter help
      create <board> <type> <title> — Create a panel
      types <board> — List available panel types
      rename <board> <panel> <new> — Rename panel
      move <board> <panel> <x> <y> — Move panel
      resize <board> <panel> <w> <h> — Resize panel
      color <board> <panel> <color|clear> — Set panel tint color
      hide <board> <panel> — Hide panel
      show <board> <panel> — Show hidden panel
      focus <board> <panel> — Focus panel (bring to front)

  panel actions (sent to panel handler):
    do <board> <panel> <action> [json] — Execute a panel action

  link commands:
    links <board> — List links
    link:
      create <board> <from> <to> — Link two panels
      delete <board> <link-id> — Remove a link by its ID
      style <board> <linkId> <arrow|line> [bezier|straight|elbow] — Set link style
      color <board> <linkId> <color> — Set link color

  shorthand commands:
    run:
      list <board> <panel> — List run configurations and sessions
      input <board> <panel> <sessionId|id|name> <text> [--enter] — Send stdin to running run session
      output <board> <panel> [sessionId|id|name] — Show output of latest matching run session
      detach <board> <panel> [sessionId|id|name] — Detach run console from session
      attach <board> <panel> [sessionId|id|name] [--any] — Attach run console to running/any session
      popout <board> <panel> [sessionId|id|name] — Create detached Run panel and attach session
    play <board> <panel> <file-or-url> — Add to playlist and play
    note:
      <board> <panel> <text> — Set markdown note content
      append <board> <panel> <text> — Append text to note
      wrap <board> <panel> — Enable auto-height
      nowrap <board> <panel> — Disable auto-height
    checklist:
      add <board> <panel> <item> — Add checklist item
      check <board> <panel> <id|text> — Check item by ID or text
      uncheck <board> <panel> <id|text> — Uncheck item by ID or text
    kanban:
      columns <board> <panel> — List kanban columns
      add-column <board> <panel> <name> — Add kanban column
      rename-column <board> <panel> <col> <new-name> — Rename column
      remove-column <board> <panel> <col> — Remove column and cards
      add-card <board> <panel> <col> <title> — Add card
      update-card <board> <panel> <cardId> <title> — Update card title
      remove-card <board> <panel> <cardId> — Remove card
      move-card <board> <panel> <cardId> <col> — Move card to column
      cards <board> <panel> — List all columns+cards
    web:
      open <board> <panel> <url> — Open URL in webpage panel
    board:
      translate <board> <x> <y> — Set viewport translation offset
```
