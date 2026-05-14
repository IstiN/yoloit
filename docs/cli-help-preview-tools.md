# CLI Help Preview (tools)

```json
{
  "tools": [
    {
      "name": "reload",
      "description": "Hot reload the running Flutter app",
      "inputSchema": {
        "type": "object",
        "properties": {},
        "additionalProperties": false
      }
    },
    {
      "name": "restart",
      "description": "Hot restart the running Flutter app",
      "inputSchema": {
        "type": "object",
        "properties": {},
        "additionalProperties": false
      }
    },
    {
      "name": "boards",
      "description": "List all boards",
      "inputSchema": {
        "type": "object",
        "properties": {},
        "additionalProperties": false
      }
    },
    {
      "name": "board",
      "description": "Show board details",
      "inputSchema": {
        "type": "object",
        "properties": {
          "id_or_name": {
            "type": "string",
            "description": "Board identifier or board name"
          }
        },
        "additionalProperties": false,
        "required": [
          "id_or_name"
        ]
      }
    },
    {
      "name": "board:create",
      "description": "Create a new board",
      "inputSchema": {
        "type": "object",
        "properties": {
          "name": {
            "type": "string",
            "description": "New board name"
          }
        },
        "additionalProperties": false,
        "required": [
          "name"
        ]
      }
    },
    {
      "name": "board:snapshot",
      "description": "Text snapshot of board layout",
      "inputSchema": {
        "type": "object",
        "properties": {
          "id_or_name": {
            "type": "string",
            "description": "Board identifier or board name"
          },
          "format": {
            "type": "string",
            "description": "Output format (default: md)"
          }
        },
        "additionalProperties": false,
        "required": [
          "id_or_name"
        ]
      }
    },
    {
      "name": "board:diagram",
      "description": "Alias for board snapshot focused on diagram output",
      "inputSchema": {
        "type": "object",
        "properties": {
          "id_or_name": {
            "type": "string",
            "description": "Board identifier or board name"
          },
          "format": {
            "type": "string",
            "description": "Output format (default: mermaid)"
          }
        },
        "additionalProperties": false,
        "required": [
          "id_or_name"
        ]
      }
    },
    {
      "name": "board:screenshot",
      "description": "Save PNG screenshot",
      "inputSchema": {
        "type": "object",
        "properties": {
          "id_or_name": {
            "type": "string",
            "description": "Board identifier or board name"
          },
          "file_png": {
            "type": "string",
            "description": "Output PNG path"
          }
        },
        "additionalProperties": false,
        "required": [
          "id_or_name"
        ]
      }
    },
    {
      "name": "board:svg",
      "description": "Export SVG layout",
      "inputSchema": {
        "type": "object",
        "properties": {
          "id_or_name": {
            "type": "string",
            "description": "Board identifier or board name"
          },
          "file_svg": {
            "type": "string",
            "description": "Output SVG path"
          }
        },
        "additionalProperties": false,
        "required": [
          "id_or_name"
        ]
      }
    },
    {
      "name": "board:apply",
      "description": "Apply YAML bulk operations from file or stdin",
      "inputSchema": {
        "type": "object",
        "properties": {
          "id_or_name": {
            "type": "string",
            "description": "Board identifier or board name"
          },
          "file_or": {
            "type": "string",
            "description": "YAML file path or '-' for stdin"
          }
        },
        "additionalProperties": false,
        "required": [
          "id_or_name"
        ]
      }
    },
    {
      "name": "panels",
      "description": "List panels on board",
      "inputSchema": {
        "type": "object",
        "properties": {
          "board": {
            "type": "string",
            "description": "Board id or name"
          }
        },
        "additionalProperties": false,
        "required": [
          "board"
        ]
      }
    },
    {
      "name": "panel",
      "description": "Show panel details and content",
      "inputSchema": {
        "type": "object",
        "properties": {
          "board": {
            "type": "string",
            "description": "Board id or name"
          },
          "panel": {
            "type": "string",
            "description": "Panel id or title"
          }
        },
        "additionalProperties": false,
        "required": [
          "board",
          "panel"
        ]
      }
    },
    {
      "name": "panel:help",
      "description": "Show dynamic panel actions with parameter docs",
      "inputSchema": {
        "type": "object",
        "properties": {
          "board": {
            "type": "string",
            "description": "Board id or name"
          },
          "panel": {
            "type": "string",
            "description": "Panel id or title"
          }
        },
        "additionalProperties": false,
        "required": [
          "board",
          "panel"
        ]
      }
    },
    {
      "name": "do",
      "description": "Execute panel action",
      "inputSchema": {
        "type": "object",
        "properties": {
          "board": {
            "type": "string",
            "description": "Board id or name"
          },
          "panel": {
            "type": "string",
            "description": "Panel id or title"
          },
          "action": {
            "type": "string",
            "description": "Action name from panel:help"
          },
          "json": {
            "type": "string",
            "description": "JSON body (optional)"
          }
        },
        "additionalProperties": false,
        "required": [
          "board",
          "panel",
          "action"
        ]
      }
    },
    {
      "name": "run:list",
      "description": "List run configurations and sessions",
      "inputSchema": {
        "type": "object",
        "properties": {
          "board": {
            "type": "string",
            "description": "Board id or name"
          },
          "panel": {
            "type": "string",
            "description": "Run panel id or title"
          }
        },
        "additionalProperties": false,
        "required": [
          "board",
          "panel"
        ]
      }
    },
    {
      "name": "run:input",
      "description": "Send stdin to running run session",
      "inputSchema": {
        "type": "object",
        "properties": {
          "board": {
            "type": "string",
            "description": "Board id or name"
          },
          "panel": {
            "type": "string",
            "description": "Run panel id or title"
          },
          "sessionid_or_id_or_name": {
            "type": "string",
            "description": "Session or config selector"
          },
          "text": {
            "type": "string",
            "description": "Input text"
          },
          "enter": {
            "type": "string",
            "description": "Append newline"
          }
        },
        "additionalProperties": false,
        "required": [
          "board",
          "panel",
          "sessionid_or_id_or_name",
          "text"
        ]
      }
    },
    {
      "name": "run:attach",
      "description": "Attach run console to matching session",
      "inputSchema": {
        "type": "object",
        "properties": {
          "board": {
            "type": "string",
            "description": "Board id or name"
          },
          "panel": {
            "type": "string",
            "description": "Run panel id or title"
          },
          "sessionid_or_id_or_name": {
            "type": "string",
            "description": "Session or config selector"
          },
          "any": {
            "type": "string",
            "description": "Allow stopped sessions"
          }
        },
        "additionalProperties": false,
        "required": [
          "board",
          "panel"
        ]
      }
    },
    {
      "name": "run:popout",
      "description": "Open detached session in a new Run panel",
      "inputSchema": {
        "type": "object",
        "properties": {
          "board": {
            "type": "string",
            "description": "Board id or name"
          },
          "panel": {
            "type": "string",
            "description": "Run panel id or title"
          },
          "sessionid_or_id_or_name": {
            "type": "string",
            "description": "Session or config selector"
          }
        },
        "additionalProperties": false,
        "required": [
          "board",
          "panel"
        ]
      }
    },
    {
      "name": "links",
      "description": "List links on board",
      "inputSchema": {
        "type": "object",
        "properties": {
          "board": {
            "type": "string",
            "description": "Board id or name"
          }
        },
        "additionalProperties": false,
        "required": [
          "board"
        ]
      }
    },
    {
      "name": "link:create",
      "description": "Create panel link",
      "inputSchema": {
        "type": "object",
        "properties": {
          "board": {
            "type": "string",
            "description": "Board id or name"
          },
          "from": {
            "type": "string",
            "description": "Source panel"
          },
          "to": {
            "type": "string",
            "description": "Target panel"
          }
        },
        "additionalProperties": false,
        "required": [
          "board",
          "from",
          "to"
        ]
      }
    }
  ]
}
```
