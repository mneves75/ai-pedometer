import fs from "node:fs";
import path from "node:path";

const TYPES = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".woff2": "font/woff2", ".ttf": "font/ttf" };

export function createStaticHandler(root) {
  const canonicalRoot = fs.realpathSync(root);
  return (req, res) => {
    let pathname;
    try {
      pathname = decodeURIComponent(new URL(req.url, "http://localhost").pathname);
      if (pathname.includes("\0")) throw new URIError("NUL in path");
    } catch {
      res.writeHead(400).end();
      return;
    }

    let file;
    try {
      file = fs.realpathSync(path.join(canonicalRoot, pathname));
      const relative = path.relative(canonicalRoot, file);
      if (relative === ".." || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative) || !fs.statSync(file).isFile()) {
        res.writeHead(404).end();
        return;
      }
    } catch {
      res.writeHead(404).end();
      return;
    }

    const stream = fs.createReadStream(file);
    stream.on("error", () => {
      if (res.headersSent) res.destroy();
      else res.writeHead(404).end();
    });
    stream.on("open", () => {
      res.writeHead(200, { "content-type": TYPES[path.extname(file)] ?? "application/octet-stream" });
      stream.pipe(res);
    });
  };
}
