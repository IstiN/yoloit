#!/usr/bin/env python3
"""YoLoIT Command Router Server - keeps fused model warm in memory."""
import http.server
import json
import re
import os
import time
import sys

# Model path
MODEL_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "command_catalog", "models", "yoloit-router-v4")
if not os.path.exists(MODEL_DIR):
    # Fallback to registered model
    MODEL_DIR = os.path.expanduser("~/Library/Application Support/flutter_local_models/models/yoloit-router-v4")

SYSTEM = 'Route user text to YoLoIT CLI command. Reply ONLY JSON: {"c":"CMD","a":["ARG"]}. No markdown, no thinking, no explanation.'

ALIAS = {
    'board:show':'panels','board:switch':'board:use','board:reduce':'board:fit',
    'boards:list':'boards','checklist:create':'checklist:new',
    'checklist:mark':'checklist:check','checklist:mark-done':'checklist:check',
    'checklist:toggle':'checklist:check','models':'models:list',
    'model:select':'models:select','model:delete':'models:delete',
    'model:download':'models:download','link:open':'web:open',
    'webpage:open':'web:open','widget:create':'app:create',
    'yolochat:history':'yolochat:messages','chat:history':'yolochat:messages',
    'board:generate-screenshot':'board:screenshot','board:generate':'board:snapshot',
    'panel:close':'panel:hide','note:write':'note:add',
    'board:copy':'board:clone','board:config':'board:settings',
    'board:translate':'board:use','note:delete':'panel:delete',
    'panel:stop':'panel:hide','run:script':'run:attach',
}

print(f"Loading model from {MODEL_DIR}...")
from mlx_lm import load, generate
model, tokenizer = load(MODEL_DIR)
print("Model loaded and warm!")

class RouterHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args): pass  # Suppress logs
    
    def do_POST(self):
        if self.path != "/route":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length))
        text = body.get("text", "")
        
        messages = [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": text},
        ]
        prompt = tokenizer.apply_chat_template(messages, add_generation_prompt=True, tokenize=False)
        
        t0 = time.time()
        result = generate(model, tokenizer, prompt=prompt, max_tokens=60, verbose=False)
        elapsed_ms = int((time.time() - t0) * 1000)
        
        # Parse JSON
        m = re.search(r'"c"\s*:\s*"([^"]+)"', result)
        cmd = m.group(1) if m else ""
        args_m = re.search(r'"a"\s*:\s*\[([^\]]*)\]', result)
        args = []
        if args_m:
            args = [s.strip().strip('"') for s in args_m.group(1).split(",") if s.strip().strip('"')]
        
        # Apply alias fix
        if cmd in ALIAS:
            cmd = ALIAS[cmd]
        
        response = json.dumps({"command": cmd, "args": args, "elapsed_ms": elapsed_ms})
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(response.encode())
    
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"ok":true}')
        else:
            self.send_error(404)

port = int(sys.argv[1]) if len(sys.argv) > 1 else 9384
# Save port to file
port_file = os.path.expanduser("~/.config/yoloit/router.port")
os.makedirs(os.path.dirname(port_file), exist_ok=True)
with open(port_file, "w") as f:
    f.write(str(port))

server = http.server.HTTPServer(("127.0.0.1", port), RouterHandler)
print(f"Router server listening on port {port}")
server.serve_forever()
