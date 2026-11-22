export const name = "verification-reviewer-policy";
export const inject = ["tools"];

export function apply(ctx) {
  const shell = process.platform === "win32" ? "pwsh" : "bash";
  ctx.tools.restrict({ allow: ["read", "read_image", "glob", "grep", shell] });
}
