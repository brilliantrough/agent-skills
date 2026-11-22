import { mkdir, writeFile } from "node:fs/promises";
await mkdir("lib", { recursive: true });
await writeFile("lib/client.js", "export const client = true;\n");
