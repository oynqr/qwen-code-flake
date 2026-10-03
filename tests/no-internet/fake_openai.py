import json, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG = open(sys.argv[2], "a")


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype="application/json"):
        b = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        LOG.write(f"GET {self.path}\n")
        LOG.flush()
        self._send(200, json.dumps({"object": "list", "data": [{"id": "local-model", "object": "model", "owned_by": "local"}]}))

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        req = json.loads(self.rfile.read(n) or b"{}")
        LOG.write(f"POST {self.path} stream={req.get('stream')}\n")
        LOG.flush()
        text = "Hello from the local LLM."
        if req.get("stream"):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Connection", "close")
            self.end_headers()
            base = {"id": "c1", "object": "chat.completion.chunk", "created": int(time.time()), "model": "local-model"}
            for ch in [
                {"delta": {"role": "assistant", "content": text}, "index": 0, "finish_reason": None},
                {"delta": {}, "index": 0, "finish_reason": "stop"},
            ]:
                self.wfile.write(f"data: {json.dumps({**base, 'choices': [ch]})}\n\n".encode())
            usage = {"prompt_tokens": 10, "completion_tokens": 6, "total_tokens": 16}
            self.wfile.write(f"data: {json.dumps({**base, 'choices': [], 'usage': usage})}\n\n".encode())
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
            self.close_connection = True
        else:
            self._send(200, json.dumps({
                "id": "c1", "object": "chat.completion", "created": int(time.time()), "model": "local-model",
                "choices": [{"index": 0, "message": {"role": "assistant", "content": text}, "finish_reason": "stop"}],
                "usage": {"prompt_tokens": 10, "completion_tokens": 6, "total_tokens": 16},
            }))


ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
