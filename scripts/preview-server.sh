#!/bin/bash
# preview-server.sh — Serve screenshots + Cloudflare tunnel.
# Run in Terminal 2. Prints the iPhone URL once tunnel is up.

PREVIEW_DIR="/tmp/timed-preview"
PORT=8765

mkdir -p "$PREVIEW_DIR"

# Auto-refresh HTML page (checks for image changes every 2s without hard reload)
cat > "$PREVIEW_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
  <title>Timed — Live Preview</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      background: #111;
      display: flex;
      flex-direction: column;
      align-items: center;
      min-height: 100vh;
      font-family: -apple-system, sans-serif;
    }
    #bar {
      width: 100%;
      background: #1e1e1e;
      border-bottom: 1px solid #333;
      padding: 8px 12px;
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    #ts { color: #888; font-size: 12px; }
    #status { font-size: 12px; }
    .ok  { color: #4ade80; }
    .err { color: #f87171; }
    img {
      max-width: 100%;
      height: auto;
      display: block;
      border: 1px solid #333;
    }
  </style>
</head>
<body>
  <div id="bar">
    <span id="ts">Loading…</span>
    <span id="status" class="ok">●</span>
  </div>
  <img id="preview" src="preview.png" />
  <script>
    var lastMod = '';
    function poll() {
      fetch('preview.png?' + Date.now(), { method: 'HEAD' })
        .then(function(r) {
          var m = r.headers.get('last-modified') || r.headers.get('etag') || Date.now().toString();
          if (m !== lastMod) {
            lastMod = m;
            document.getElementById('preview').src = 'preview.png?' + Date.now();
            document.getElementById('ts').textContent = 'Updated ' + new Date().toLocaleTimeString();
            document.getElementById('status').className = 'ok';
            document.getElementById('status').textContent = '●';
          }
        })
        .catch(function() {
          document.getElementById('status').className = 'err';
          document.getElementById('status').textContent = '●';
        });
    }
    setInterval(poll, 2000);
  </script>
</body>
</html>
EOF

# Start Python HTTP server
echo "🖥  Starting preview server on port $PORT…"
python3 -m http.server $PORT --directory "$PREVIEW_DIR" &
SERVER_PID=$!

echo "🌐 Starting Cloudflare tunnel…"
echo ""
cloudflared tunnel --url "http://localhost:$PORT" 2>&1 | while IFS= read -r line; do
    echo "$line"
    if echo "$line" | grep -qoE 'https://[a-z0-9-]+\.trycloudflare\.com'; then
        URL=$(echo "$line" | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com')
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  📱 OPEN ON iPHONE:"
        echo "  $URL"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    fi
done

wait $SERVER_PID
