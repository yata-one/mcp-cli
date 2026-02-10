#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

PATH="$HOME/.moon/bin:$PATH"

moon build --target native --release cli
cli="$root/_build/native/release/build/cli/cli.exe"

tmp="$(mktemp -d /tmp/mcp-cli-e2e.XXXXXX)"
port_file="$tmp/port.txt"

cleanup() {
  if [[ -n "${http_pid:-}" ]]; then
    kill "$http_pid" 2>/dev/null || true
    wait "$http_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

python3 -u - "$port_file" <<'PY' &
import json, sys
from http.server import HTTPServer, BaseHTTPRequestHandler

port_file = sys.argv[1]

def read_body(rfile, headers):
    if headers.get("transfer-encoding", "").lower() == "chunked":
        chunks = []
        while True:
            line = rfile.readline()
            if not line:
                break
            line = line.strip()
            if not line:
                continue
            size = int(line, 16)
            if size == 0:
                # Final CRLF (and optional trailers) — consume until blank line.
                while True:
                    tail = rfile.readline()
                    if not tail or tail in (b"\r\n", b"\n"):
                        break
                break
            chunks.append(rfile.read(size))
            rfile.read(2)  # \r\n
        return b"".join(chunks)
    length = int(headers.get("content-length", "0"))
    return rfile.read(length)

def rpc_method(msg):
    return msg.get("method", "")

def rpc_id(msg, default=1):
    return msg.get("id", default)

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        raw = read_body(self.rfile, {k.lower(): v for k, v in self.headers.items()}).decode("utf-8")
        msg = json.loads(raw) if raw else {}
        method = rpc_method(msg)

        def send_json(obj, code=200):
            data = json.dumps(obj).encode("utf-8")
            self.send_response(code)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        if method == "initialize":
            result = {
                "protocolVersion": "2025-03-26",
                "capabilities": {},
                "serverInfo": {"name": "mock"},
                "instructions": "hello\nworld",
            }
            resp = {"jsonrpc": "2.0", "id": rpc_id(msg, 1), "result": result}
            send_json(resp)
            return

        if method == "notifications/initialized":
            self.send_response(202)
            self.end_headers()
            return

        if method == "tools/list":
            tools = [
                {
                    "name": "echo",
                    "description": "Echo text",
                    "inputSchema": {
                        "type": "object",
                        "properties": {"text": {"type": "string"}},
                        "required": ["text"],
                    },
                },
                {
                    "name": "no_text",
                    "description": "No text result",
                    "inputSchema": {"type": "object"},
                },
            ]
            resp = {
                "jsonrpc": "2.0",
                "id": rpc_id(msg, 2),
                "result": {"tools": tools},
            }
            send_json(resp)
            return

        if method == "tools/call":
            params = msg.get("params", {})
            name = params.get("name", "")
            args = params.get("arguments", {}) or {}
            if name == "echo":
                text = args.get("text", "")
                result = {"content": [{"type": "text", "text": text}]}
            else:
                result = {"content": [{"type": "image", "url": "x"}]}
            resp = {"jsonrpc": "2.0", "id": rpc_id(msg, 3), "result": result}
            send_json(resp)
            return

        self.send_response(500)
        self.end_headers()

    def log_message(self, format, *args):
        # silence
        pass

httpd = HTTPServer(("127.0.0.1", 0), Handler)
port = httpd.server_address[1]
with open(port_file, "w") as f:
    f.write(str(port))
    f.flush()
httpd.serve_forever()
PY
http_pid=$!

port=""
for _ in {1..50}; do
  if [[ -s "$port_file" ]]; then
    port="$(cat "$port_file")"
    break
  fi
  sleep 0.05
done
if [[ -z "$port" ]]; then
  echo "failed to start mock http server" >&2
  exit 1
fi

cfg="$tmp/http.json"
cat >"$cfg" <<EOF
{
  // JSONC + trailing commas
  "mcpServers": {
    "srv": { "url": "http://127.0.0.1:$port/mcp", },
  },
}
EOF

env_cmd=(env MCP_NO_DAEMON=1 MCP_MAX_RETRIES=0 MCP_TIMEOUT=2)

echo "[http] list"
out="$("${env_cmd[@]}" "$cli" -c "$cfg")"
expected=$'srv: hello\n  tools:\n    - srv/echo: Echo text\n    - srv/no_text: No text result'
[[ "$out" == "$expected" ]]

echo "[config] skill config discovery"
home="$tmp/home"
mkdir -p "$home/.agents/skills/test-skill"
cat >"$home/.agents/skills/test-skill/mcp-cli.jsonc" <<EOF
{
  "mcpServers": {
    "srv": { "url": "http://127.0.0.1:$port/mcp" }
  }
}
EOF
work="$tmp/work"
mkdir -p "$work"
out="$(cd "$work" && env HOME="$home" MCP_NO_DAEMON=1 MCP_MAX_RETRIES=0 MCP_TIMEOUT=2 "$cli")"
[[ "$out" == "$expected" ]]

echo "[config] project config discovery (.jsonc)"
proj="$tmp/proj"
mkdir -p "$proj/.git" "$proj/.agents" "$proj/sub"
cat >"$proj/.agents/mcp-cli.jsonc" <<EOF
{
  "mcpServers": {
    "srv": { "url": "http://127.0.0.1:$port/mcp" }
  }
}
EOF
empty_home="$tmp/empty_home"
mkdir -p "$empty_home"
out="$(cd "$proj/sub" && env HOME="$empty_home" MCP_NO_DAEMON=1 MCP_MAX_RETRIES=0 MCP_TIMEOUT=2 "$cli")"
[[ "$out" == "$expected" ]]

echo "[http] grep"
out="$("${env_cmd[@]}" "$cli" -c "$cfg" grep '*o*')"
expected=$'List grep results (<server>/<tool> in detail):\n\nsrv/echo: Echo text\n\nsrv/no_text: No text result'
[[ "$out" == "$expected" ]]

echo "[http] call echo (text-first)"
out="$("${env_cmd[@]}" "$cli" -c "$cfg" call srv echo '{"text":"hi"}')"
[[ "$out" == "hi" ]]

echo "[http] call no_text (json fallback)"
out="$("${env_cmd[@]}" "$cli" -c "$cfg" call srv no_text '{}')"
[[ "$out" == \{* ]]

echo "[cli] ambiguous server/tool requires subcommand"
set +e
err="$("${env_cmd[@]}" "$cli" -c "$cfg" srv/echo 2>&1 >/dev/null)"
code="$?"
set -e
[[ "$code" == "1" ]]
[[ "$err" == *"ambiguous command"* ]]

echo "[network] connection refused => exit 3"
unused_port="$(
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
p = s.getsockname()[1]
s.close()
print(p)
PY
)"
bad="$tmp/bad.json"
cat >"$bad" <<EOF
{ "mcpServers": { "bad": { "url": "http://127.0.0.1:$unused_port/mcp" } } }
EOF
set +e
"${env_cmd[@]}" "$cli" -c "$bad" info bad >/dev/null 2>&1
code="$?"
set -e
[[ "$code" == "3" ]]

echo "[stdio] call"
stdio_py="$tmp/stdio_server.py"
cat >"$stdio_py" <<'PY'
import json, sys

def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    msg = json.loads(line)
    method = msg.get("method", "")
    if method == "initialize":
        send({
            "jsonrpc": "2.0",
            "id": msg.get("id", 1),
            "result": {
                "protocolVersion": "2025-03-26",
                "capabilities": {},
                "serverInfo": {"name": "stdio-mock"},
                "instructions": "hi",
            }
        })
    elif method == "tools/list":
        send({
            "jsonrpc": "2.0",
            "id": msg.get("id", 2),
            "result": {
                "tools": [
                    {"name":"echo","description":"Echo text","inputSchema":{"type":"object"}}
                ]
            }
        })
    elif method == "tools/call":
        params = msg.get("params", {})
        args = params.get("arguments", {}) or {}
        text = args.get("text", "")
        send({
            "jsonrpc": "2.0",
            "id": msg.get("id", 3),
            "result": {"content":[{"type":"text","text":text}]}
        })
    else:
        # ignore notifications
        pass
PY

stdio_cfg="$tmp/stdio.json"
cat >"$stdio_cfg" <<EOF
{
  "mcpServers": {
    "s": { "command": "python3", "args": ["-u", "$stdio_py"] }
  }
}
EOF

out="$("${env_cmd[@]}" "$cli" -c "$stdio_cfg" call s echo '{"text":"hi"}')"
[[ "$out" == "hi" ]]

echo "OK: e2e passed"
