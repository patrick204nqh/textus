import { execSync } from "child_process"
import fs from "fs"
import path from "path"

const STATE_DIR = path.join(process.env.HOME || process.cwd(), ".config", "opencode", "textus")
const STATE_FILE = path.join(STATE_DIR, "state.json")

function generateId() {
  return Math.random().toString(36).slice(2, 10)
}

function readState() {
  try {
    return JSON.parse(fs.readFileSync(STATE_FILE, "utf8"))
  } catch {
    const state = { session_id: generateId(), session_start_ts: Date.now() }
    fs.mkdirSync(STATE_DIR, { recursive: true })
    fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2))
    return state
  }
}

function bootData() {
  try {
    return JSON.parse(execSync("bundle exec exe/textus boot", { encoding: "utf8", timeout: 10000 }))
  } catch {
    return null
  }
}

function loopData() {
  try {
    return JSON.parse(execSync("bundle exec exe/textus loop", { encoding: "utf8", timeout: 5000 }))
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

function toast(client, message, variant) {
  try {
    client.tui.showToast({ body: { message, variant: variant || "info" } })
  } catch (_) {}
}

const TextusPlugin = async (ctx) => {
  const boot = bootData()
  if (!boot) return {}

  const paths = boot.plugin?.protected_paths || []
  const state = readState()

  toast(ctx.client, "textus loaded — " + state.session_id, "info")

  return {
    event: async ({ event }) => {
      if (event.type === "session.created" || event.type === "session.updated") {
        try {
          const loop = loopData()
          const node = loop?.current_node?.name || "—"
          const sid = event.session_id?.slice(0, 8) || state.session_id
          execSync(`printf '\\e]0;textus — ${node} — ${sid}\\a'`, { timeout: 1000 })
          toast(ctx.client, "textus — " + node + " — " + sid, "info")
        } catch (_) {}
      }
    },

    "chat.message": async (_input, output) => {
      try {
        const loop = loopData()
        const node = loop?.current_node?.name || "—"
        const line = "■ loop:" + node + "  ◆ ses:" + state.session_id + "  ● role:agent  │  textus — use `textus propose` for protected files"

        if (!output.parts) output.parts = []
        const idx = output.parts.findIndex((p) => p && p.type === "text" && typeof p.text === "string")
        if (idx >= 0) {
          output.parts[idx].text = line + "\n\n" + (output.parts[idx].text ?? "")
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
          toast(ctx.client, "[textus] Blocked: " + fp, "error")
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
