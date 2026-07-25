import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { createServer } from "node:http";
import { extname, normalize, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(fileURLToPath(new URL(".", import.meta.url)));
const port = Number(process.env.PORT || 4173);
const mime = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
};

const server = createServer(async (request, response) => {
  try {
    const url = new URL(request.url, `http://${request.headers.host || "localhost"}`);
    const relative = normalize(decodeURIComponent(url.pathname === "/" ? "/index.html" : url.pathname)).replace(/^[/\\]+/, "");
    const file = resolve(root, relative);
    if (file !== root && !file.startsWith(`${root}${sep}`)) throw Object.assign(new Error("Forbidden"), { status: 403 });
    const info = await stat(file);
    if (!info.isFile()) throw Object.assign(new Error("Not found"), { status: 404 });
    response.writeHead(200, {
      "Content-Type": mime[extname(file)] || "application/octet-stream",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    });
    createReadStream(file).pipe(response);
  } catch (error) {
    response.writeHead(error.status || 404, { "Content-Type": "text/plain; charset=utf-8" });
    response.end(error.status === 403 ? "Forbidden" : "Not found");
  }
});

server.listen(port, "127.0.0.1", () => {
  console.log(`Sovereign Interior: http://127.0.0.1:${port}`);
});
