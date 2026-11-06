export const name = "consolidation-reviewer-policy";
export const inject = ["tools"];

export function apply(ctx) {
  ctx.tools.restrict({ allow: ["read", "read_image", "glob", "grep"] });
}
