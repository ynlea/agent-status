// agent-status realtime pi extension.
//
// Reports pi session state and token usage to the agent-status server the
// moment they happen, instead of waiting for the monitor's periodic file scan:
//   - before_agent_start -> working (user submitted a prompt)
//   - agent_settled      -> idle   (agent will not continue automatically)
//   - session_shutdown   -> idle   (session closed)
//   - message_end        -> usage  (assistant / toolResult messages)
//
// The extension also writes ~/.agent-status/pi-ext-state.json as the
// coordination channel with the monitor: while a session's ext state is fresh
// (<= 3 min), the file scan honors the realtime state instead of re-inferring
// it from staleness, so an ended session flips to idle immediately.
//
// Install: copy this file to ~/.pi/agent/extensions/agent-status.ts and
// restart pi. Config falls back to the monitor config file when env vars are
// absent (AGENT_STATUS_SERVER_URL / AGENT_STATUS_KEY / AGENT_STATUS_MACHINE_ID).
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const env = process.env;
const EXT_STATE_FILE = join(homedir(), ".agent-status", "pi-ext-state.json");

interface MonitorConfig {
  server_url?: string;
  key?: string;
  machine_id?: string;
  machine_name?: string;
  platform?: string;
}

function loadMonitorConfig(): MonitorConfig {
  const candidates = [
    env.AGENT_STATUS_MONITOR_CONFIG,
    join(homedir(), ".local/share/agent-status/config/monitor.json"),
    "monitor.json",
  ];
  for (const c of candidates) {
    if (!c || !existsSync(c)) continue;
    try {
      return JSON.parse(readFileSync(c, "utf8")) as MonitorConfig;
    } catch {
      // keep looking
    }
  }
  return {};
}

const cfg = loadMonitorConfig();
const serverUrl = (env.AGENT_STATUS_SERVER_URL ?? cfg.server_url ?? "").replace(/\/+$/, "");
const apiKey = env.AGENT_STATUS_KEY ?? cfg.key ?? "";
const machineId = env.AGENT_STATUS_MACHINE_ID ?? cfg.machine_id ?? "";
const machineName = env.AGENT_STATUS_MACHINE_NAME ?? cfg.machine_name ?? "";
const platform = env.AGENT_STATUS_PLATFORM ?? cfg.platform ?? "linux";

// --- session id ---------------------------------------------------------------

// File names look like <timestamp>_<uuid>.jsonl; the uuid is the session id.
function sessionIdFromFile(file: string | null | undefined): string {
  const stem = (file ?? "").split("/").pop()?.replace(/\.jsonl$/, "") ?? "";
  const i = stem.lastIndexOf("_");
  return i >= 0 && i < stem.length - 1 ? stem.slice(i + 1) : stem;
}

// --- extension state file (coordination with the monitor scan) ----------------

interface ExtEntry {
  state: string;
  updated_at: string;
  display_name?: string;
  cwd?: string;
  message?: string;
}

interface ExtState {
  sessions: Record<string, ExtEntry>;
}

function loadExtState(): ExtState {
  try {
    return JSON.parse(readFileSync(EXT_STATE_FILE, "utf8")) as ExtState;
  } catch {
    return { sessions: {} };
  }
}

function saveExtState(st: ExtState): void {
  const cutoff = Date.now() - 7 * 24 * 3600 * 1000;
  for (const [k, v] of Object.entries(st.sessions)) {
    const t = new Date(v.updated_at).getTime();
    if (Number.isNaN(t) || t < cutoff) delete st.sessions[k];
  }
  mkdirSync(join(homedir(), ".agent-status"), { recursive: true });
  const tmp = EXT_STATE_FILE + ".tmp";
  writeFileSync(tmp, JSON.stringify(st));
  try {
    renameSync(tmp, EXT_STATE_FILE);
  } catch {
    writeFileSync(EXT_STATE_FILE, JSON.stringify(st));
  }
}

// --- HTTP reporting -----------------------------------------------------------

interface ReportSession {
  machine_id: string;
  machine_name: string;
  agent: string;
  session_id: string;
  display_name: string;
  state: string;
  message: string;
  cwd: string;
  source: string;
  updated_at: string;
}

interface UsageEvent {
  dedupe_key: string;
  agent: string;
  model: string;
  session_id: string;
  occurred_at: string;
  input_tokens: number;
  output_tokens: number;
  reasoning_tokens: number;
  cache_write_tokens: number;
  cache_hit_tokens: number;
}

async function post(path: string, body: unknown): Promise<void> {
  if (!serverUrl || !apiKey) return;
  try {
    const res = await fetch(serverUrl + path, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify(body),
    });
    if (res.status >= 300) {
      console.error(`[agent-status] ${path} status ${res.status}`);
    }
  } catch (e) {
    console.error("[agent-status] report failed:", e);
  }
}

// Minimal structural view of the extension context: only what we use.
interface ExtCtx {
  sessionManager: { getSessionFile(): string | null };
}

function reportState(ctx: ExtCtx, state: string, message = ""): void {
  const file = ctx.sessionManager.getSessionFile();
  const sid = sessionIdFromFile(file ?? "");
  if (!sid) return;
  const now = new Date().toISOString();
  const st = loadExtState();
  st.sessions[sid] = {
    state,
    updated_at: now,
    display_name: st.sessions[sid]?.display_name,
    cwd: st.sessions[sid]?.cwd,
    message,
  };
  saveExtState(st);
  void post("/api/v1/report", {
    machine_id: machineId,
    machine_name: machineName,
    platform,
    reported_at: now,
    sessions: [
      {
        machine_id: machineId,
        machine_name: machineName,
        agent: "pi",
        session_id: sid,
        display_name: st.sessions[sid]?.display_name ?? "",
        state,
        message,
        cwd: st.sessions[sid]?.cwd ?? "",
        source: "pi-ext",
        updated_at: now,
      } satisfies ReportSession,
    ],
  });
}

export default function (pi: ExtensionAPI): void {
  // User submitted a prompt: the agent starts working.
  pi.on("before_agent_start", (event, ctx) => {
    const prompt = String(event.prompt ?? "").trim();
    reportState(ctx, "working", prompt.slice(0, 120));
  });

  // Agent run finished and pi will not continue automatically.
  pi.on("agent_settled", (_event, ctx) => {
    reportState(ctx, "idle");
  });

  // Session closed / switched away.
  pi.on("session_shutdown", (_event, ctx) => {
    reportState(ctx, "idle");
  });

  // Report usage the moment a message lands; dedupe_key matches the monitor's
  // ParsePiUsageFile ("pi:<file>:<message timestamp>"), so the server-side
  // dedupe collapses the realtime event and the later file scan into one row.
  pi.on("message_end", (event, ctx) => {
    const m = event.message as {
      role?: string;
      model?: string;
      timestamp?: number;
      usage?: {
        input?: number;
        output?: number;
        cacheRead?: number;
        cacheWrite?: number;
        reasoning?: number;
      };
    } | undefined;
    if (!m || (m.role !== "assistant" && m.role !== "toolResult") || !m.usage) return;
    const usage = m.usage;
    const input = usage.input ?? 0;
    const output = usage.output ?? 0;
    const cacheWrite = usage.cacheWrite ?? 0;
    const cacheRead = usage.cacheRead ?? 0;
    const reasoning = usage.reasoning ?? 0;
    if (input + output + cacheWrite + cacheRead + reasoning === 0) return;
    if (typeof m.timestamp !== "number" || m.timestamp <= 0) return;
    const file = ctx.sessionManager.getSessionFile();
    const base = (file ?? "").split("/").pop() ?? "";
    const sid = sessionIdFromFile(file ?? "");
    if (!base || !sid) return;
    void post("/api/v1/usage/report", {
      machine_id: machineId,
      machine_name: machineName,
      platform,
      reported_at: new Date().toISOString(),
      events: [
        {
          dedupe_key: `pi:${base}:${String(m.timestamp)}`,
          agent: "pi",
          model: m.model ?? "unknown",
          session_id: sid,
          occurred_at: new Date(m.timestamp).toISOString(),
          input_tokens: input,
          output_tokens: output,
          reasoning_tokens: reasoning,
          cache_write_tokens: cacheWrite,
          cache_hit_tokens: cacheRead,
        } satisfies UsageEvent,
      ],
    });
  });
}
