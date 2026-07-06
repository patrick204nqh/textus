import { execSync } from "child_process"

function bootData() {
  try {
    const raw = execSync("bundle exec exe/textus boot", { encoding: "utf8", timeout: 10000 })
    return JSON.parse(raw)
  } catch {
    return null
  }
}

function loopData() {
  try {
    const raw = execSync("bundle exec exe/textus loop", { encoding: "utf8", timeout: 5000 })
    return JSON.parse(raw)
  } catch {
    return null
  }
}

function getFilePath(args) {
  if (!args || typeof args !== "object") return null
  return args.filePath || args.path || args.file_path || null
}

function isMutation(tool) {
  return tool === "edit" || tool === "write" || tool === "patch"
}

const TextusPlugin = async (ctx) => {
  const boot = bootData()
  if (!boot) return {}

  const paths = boot.plugin?.protected_paths || []
  const projectName = boot.project?.name || "textus"

  return {
    "chat.message": async (_input, output) => {
      try {
        const loop = loopData()
        const node = loop?.current_node?.name || "—"

        const line = `■ ${node}  ◆ ${projectName}  │  textus protocol — use \`textus propose\` for protected files`

        if (!output.parts) output.parts = []
        const idx = output.parts.findIndex((p) => p && p.type === "text" && typeof p.text === "string")
        if (idx >= 0) {
          output.parts[idx].text = `${line}\n\n${output.parts[idx].text ?? ""}`
        } else {
          output.parts.unshift({ type: "text", text: line })
        }
      } catch (e) {
        console.error("[textus] chat.message error:", e)
      }
    },

    "tool.execute.before": async (input, output) => {
      if (!isMutation(input.tool)) return
      const fp = getFilePath(output.args)
      if (!fp) return
      for (const p of paths) {
        if (fp.startsWith(p)) {
          throw new Error(
            "[textus] Blocked write to: " + fp + "\n" +
            "This file is protected by textus — use `textus propose` to suggest changes."
          )
        }
      }
    },
  }
}

export default TextusPlugin
