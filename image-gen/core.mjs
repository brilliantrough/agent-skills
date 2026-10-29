// 文生图/图生图共用核心：Pi、DSH(pi2dsh)、OpenCode 三个宿主只做薄适配。
// 接口形状来自实调 api.pezayo.com /v1/images/generations 与 /v1/images/edits。
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, join, resolve } from "node:path";

export const TOOL = "image_gen";
export const DESCRIPTION =
  "Draw a picture with an image model and show it to the user. " +
  "Use when knowledge, a comparison, a flow or a concept is easier to grasp as a picture than as text, " +
  "and when the user asks for a diagram, overview, illustration, poster or icon. " +
  "Write the prompt yourself in the user's language: say what the picture must make obvious, name the " +
  "labels to appear in the image, and pick a readable style; never paste raw chat text as the prompt. " +
  "Pass reference images (absolute paths) to edit or restyle them. The tool returns the image itself plus " +
  "the saved path. Prefer one clear picture over many; ask before drawing something large.";

const CONFIG = process.env.IMAGE_GEN_CONFIG || join(homedir(), ".local/share/agent-skills/image-gen.json");
const MODELS = join(homedir(), ".pi/agent/models.json");
const DEFAULT_MODEL = "gpt-image-2.5-flare";
const MIME = { png: "image/png", jpeg: "image/jpeg", jpg: "image/jpeg", webp: "image/webp" };
const DEFAULTS = { output_dir: "images", size: "1024x1024", quality: "medium" };

export const configPath = () => CONFIG;

// 首次运行从 Pi 的模型表挑一个 OpenAI 协议 provider（图像接口是 OpenAI 形状），
// 挑不到就留空，由调用方报错让用户填。
async function detect() {
  const empty = { base_url: "", api_key: "", model: DEFAULT_MODEL };
  try {
    const { providers = {} } = JSON.parse(await readFile(MODELS, "utf8"));
    const entry = Object.values(providers).find((p) => p?.apiKey && p?.baseUrl && /^openai/.test(p.api ?? ""));
    return entry ? { base_url: entry.baseUrl, api_key: entry.apiKey, model: DEFAULT_MODEL } : empty;
  } catch {
    return empty;
  }
}

async function writeConfig(config) {
  await mkdir(join(homedir(), ".local/share/agent-skills"), { recursive: true });
  await writeFile(CONFIG, JSON.stringify(config, null, 2) + "\n", { mode: 0o600 });
  return CONFIG;
}

export async function loadConfig() {
  let file;
  try {
    file = JSON.parse(await readFile(CONFIG, "utf8"));
  } catch (error) {
    if (error.code !== "ENOENT") throw new Error(`${CONFIG} 不是有效 JSON：${error.message}`);
  }
  if (file?.base_url && file?.api_key) return { ...DEFAULTS, ...file };
  const detected = await detect();
  if (!detected.base_url) {
    await writeConfig(detected);
    throw new Error(`缺少图像接口凭据：填写 ${CONFIG} 的 base_url 与 api_key（可选 model，默认 ${DEFAULT_MODEL}）`);
  }
  await writeConfig(detected);
  return { ...DEFAULTS, ...detected };
}

// 参考图走 multipart /images/edits，字段名 image[] 与官方接口一致。
async function request(config, body, references, signal) {
  const headers = { Authorization: `Bearer ${config.api_key}` };
  let payload;
  let path = "/images/generations";
  if (references?.length) {
    const form = new FormData();
    for (const [key, value] of Object.entries(body)) form.append(key, String(value));
    for (const [index, file] of references.entries()) {
      const type = MIME[file.split(".").pop().toLowerCase()] ?? "image/png";
      form.append("image[]", new Blob([await readFile(file)], { type }), basename(file) || `ref-${index}.png`);
    }
    payload = form;
    path = "/images/edits";
  } else {
    headers["Content-Type"] = "application/json";
    payload = JSON.stringify(body);
  }
  const response = await fetch(config.base_url.replace(/\/+$/, "") + path, { method: "POST", signal, headers, body: payload });
  const text = await response.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    throw new Error(`图像接口返回非 JSON（HTTP ${response.status}）：${text.slice(0, 300)}`);
  }
  if (!response.ok) throw new Error(`图像接口 ${response.status}：${json.error?.message ?? text.slice(0, 300)}`);
  const b64 = json.data?.[0]?.b64_json;
  if (!b64) throw new Error(`图像接口没返回图片：${text.slice(0, 300)}`);
  return { image: Buffer.from(b64, "base64"), json };
}

const slug = (prompt) =>
  prompt.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, "-").replace(/^-|-$/g, "").slice(0, 40) || "image";

export async function generate(args, cwd, signal) {
  const config = await loadConfig();
  const model = args.model || config.model || DEFAULT_MODEL;
  const body = {
    model,
    prompt: args.prompt,
    size: args.size || config.size,
    quality: args.quality || config.quality,
    n: 1,
  };
  if (args.background) body.background = args.background;
  const { image, json } = await request(config, body, args.reference, signal);

  const format = json.output_format ?? "png";
  const dir = resolve(cwd, config.output_dir);
  await mkdir(dir, { recursive: true });
  const path = join(dir, `${new Date().toISOString().replace(/[:.]/g, "-")}-${slug(args.prompt)}.${format}`);
  await writeFile(path, image);

  return {
    path,
    mimeType: MIME[format] ?? MIME.png,
    base64: image.toString("base64"),
    note: `${model} · ${json.size ?? body.size} · ${json.quality ?? body.quality} · ${format} · ${(image.length / 1024).toFixed(0)} KB`,
  };
}
