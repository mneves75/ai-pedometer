import assert from "node:assert/strict";
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { after, test } from "node:test";
import { createStaticHandler } from "./static-handler.mjs";

const base = fs.mkdtempSync(path.join(os.tmpdir(), "render-handler-"));
const root = path.join(base, "work");
const sibling = path.join(base, "work-private");
fs.mkdirSync(root);
fs.mkdirSync(sibling);
fs.writeFileSync(path.join(root, "index.html"), "synthetic page");
fs.writeFileSync(path.join(root, "with space.html"), "encoded page");
fs.writeFileSync(path.join(sibling, "sentinel.txt"), "outside root");
fs.symlinkSync(path.join(sibling, "sentinel.txt"), path.join(root, "link.txt"));
fs.symlinkSync(path.join(root, "index.html"), path.join(root, "inside.html"));
after(() => fs.rmSync(base, { recursive: true }));

const handler = createStaticHandler(root);
const server = http.createServer(handler);
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
after(() => new Promise((resolve) => server.close(resolve)));

async function request(url) {
  return await new Promise((resolve, reject) => {
    http.get({ hostname: "127.0.0.1", port: server.address().port, path: url }, (res) => {
      let body = "";
      res.on("data", (chunk) => { body += chunk; });
      res.on("end", () => resolve({ code: res.statusCode, body, type: res.headers["content-type"] }));
    }).on("error", reject);
  });
}

for (const url of ["/%2e%2e%2fwork-private/sentinel.txt", "/link.txt", "/missing", "/"]) {
  test(`rejects outside or absent file: ${url}`, async () => {
    assert.equal((await request(url)).code, 404);
  });
}
for (const url of ["/%", "/%ZZ", "/%00"]) {
  test(`invalid path returns 400: ${url}`, async () => {
    assert.equal((await request(url)).code, 400);
    assert.equal((await request("/index.html")).code, 200);
  });
}
test("serves a valid encoded file with its content type", async () => {
  assert.deepEqual(await request("/with%20space.html?cache=1"), {
    code: 200, body: "encoded page", type: "text/html",
  });
});
test("permits a symlink whose target stays inside root", async () => {
  assert.equal((await request("/inside.html")).body, "synthetic page");
});
