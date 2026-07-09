import os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


class AppRouteHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        super().end_headers()

    def send_head(self):
        path = self.translate_path(self.path)
        route_path = self.path.split("?", 1)[0]
        if not os.path.exists(path) and not os.path.splitext(route_path)[1]:
            self.path = "/index.html"
        return super().send_head()


if __name__ == "__main__":
    os.chdir(os.path.join(os.path.dirname(__file__), "..", "build", "web"))
    ThreadingHTTPServer(("127.0.0.1", 5200), AppRouteHandler).serve_forever()
