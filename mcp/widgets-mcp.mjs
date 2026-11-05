#!/usr/bin/env node
import { readFile, mkdtemp, rm } from "node:fs/promises";
import { execFile } from "node:child_process";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";
import { promisify } from "node:util";

const port = Number(process.env.STAND_BRIDGE_PORT || 7420);
const tokenFile = process.env.STAND_BRIDGE_TOKEN_FILE || join(homedir(), ".config", "duo-stand", "token");
const run = promisify(execFile);

const schemaGuide = `Custom widget definition (JSON). Only send the fields you change; the Bridge merges them onto defaults or the saved widget.
{
  "id": "UUID (omit to create)", "name": "MOCO Woche", "symbol": "SF Symbol name",
  "baseURL": "https://api.example.com/v1", "interval": 300,
  "auth": {"kind": "none|bearer|headerKey|queryKey|basic|customHeader", "name": "Header or query name", "prefix": "Token token="},
  "endpoint": {"method": "GET|POST", "path": "items", "query": [{"name": "from", "value": "{today}"}], "headers": [], "body": "JSON text for POST"},
  "variables": [{"name": "from", "value": "Wels Hbf"}],
  "selection": {"valuePath": "data.total", "arrayPath": "data.items (aggregate instead of valuePath)", "valueField": "hours",
                "aggregation": "sum|count|countPresent|average|minimum|maximum|first|last", "filter": "status == active",
                "seriesPath": "data.items (list/bar rows)", "labelField": "date", "seriesField": "hours", "groupsLabels": false, "labelsAreDates": false,
                "labelTemplate": "{dep.time|time}", "textTemplate": "{name??title} · Gl. {platform}"},
  "values": [{"name": "booked", "selection": {...}, "format": "number|percent|hoursMinutes|clock"}],
  "display": {"style": "text|status|gauge|line|bar|list", "caption": "Woche", "format": "number|percent|hoursMinutes|clock", "decimals": 0,
              "prefix": "", "unit": "h", "suffix": "", "gaugeMin": 0, "gaugeMax": 100, "target": 38.5,
              "rules": [{"comparison": "equals|atLeast|below", "operand": "1", "tone": "green|yellow|red|blue|gray", "label": "Läuft"}],
              "lines": ["{project}"], "layout": NODE, "compact": NODE, "wide": NODE}
}
Placeholders in path, query, headers and body: {today} {yesterday} {weekStart} {weekEnd} {monthStart} {monthEnd} and every variable as {name} (JSON-escaped in bodies).
Row templates: {path} from the list element, a??b takes the first present value, filters |time |date |weekday |minutes |upper |lower.
"target" turns any style into progress toward a goal (corner arcs on the Stand edge show progress and overflow).
NODE (max 64 nodes, depth 6): {"type": "vstack|hstack|zstack|spacer|text|symbol|dot|timer|ring|bar|line|bars|list|pill|divider",
  "children": [NODE], "text": "{booked} h", "size": "xs|s|m|l|xl", "bold": true, "tone": "green", "toneWhen": [{"when": "running >= 1", "tone": "green"}],
  "when": "running >= 1", "value": "booked", "max": "40", "since": "runningStart", "spacing": 8, "align": "leading|center|trailing",
  "pulse": true, "lines": 2, "priority": 1, "color": "status", "minW": 2, "minH": 2}
Text templates in nodes use named values: {value} {caption} and every entry of "values".
Secrets (API keys) go in the separate "secret" argument and land in the Mac's keychain, never in the definition.`;

const tools = [
  {
    name: "list_widgets",
    description: "Lists the custom widgets saved in Amberlight Bridge (full definitions, no secrets) and the available templates.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "widget_schema",
    description: "Reference for the custom widget definition JSON: request, selection, row templates, display styles and layout nodes. Read before writing a definition.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "save_widget",
    description: "Creates or updates a custom widget. Pass a partial definition; with an id it patches that widget, with a template id it starts from that template. Returns the saved definition and the first live result.",
    inputSchema: {
      type: "object",
      properties: {
        definition: { type: "object", description: "Partial custom widget definition, see widget_schema." },
        template: { type: "string", description: "Template id from list_widgets to start from (only when creating)." },
        secret: { type: "object", properties: { value: { type: "string" }, username: { type: "string" } }, description: "API key or password, stored in the keychain." },
      },
      required: ["definition"],
    },
  },
  {
    name: "delete_widget",
    description: "Deletes a custom widget and its stored secret.",
    inputSchema: { type: "object", properties: { id: { type: "string" } }, required: ["id"] },
  },
  {
    name: "render_widget",
    description: "Renders a custom widget to a PNG at several grid sizes, as the Stand shows it. Either a saved widget by id (fetches live data), or a definition plus sample JSON to design without calling the API.",
    inputSchema: {
      type: "object",
      properties: {
        id: { type: "string" },
        definition: { type: "object", description: "Partial definition to try (needs sample)." },
        sample: { description: "Sample API response used instead of a live request." },
        sizes: { type: "array", items: { type: "string" }, description: "Grid spans like 1x1, 2x1, 2x2, 3x2, 6x4. Default 1x1, 2x1, 2x2, 3x2." },
        dimmed: { type: "boolean", description: "Night mode rendering." },
      },
    },
  },
  {
    name: "screenshot_simulator",
    description: "Takes a screenshot of the booted iOS Simulator, to see the widget on the real Stand app.",
    inputSchema: { type: "object", properties: { device: { type: "string", description: "Simulator UDID or name, default booted." } } },
  },
];

async function bridge(method, path, body) {
  const token = (await readFile(tokenFile, "utf8")).trim();
  const response = await fetch(`http://127.0.0.1:${port}${path}`, {
    method,
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const json = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(json.error || `Bridge antwortet ${response.status} auf ${method} ${path}`);
  return json;
}

const text = (value) => ({ type: "text", text: typeof value === "string" ? value : JSON.stringify(value, null, 2) });

async function call(name, args = {}) {
  switch (name) {
    case "list_widgets":
      return [text(await bridge("GET", "/studio/widgets"))];
    case "widget_schema":
      return [text(schemaGuide)];
    case "save_widget":
      return [text(await bridge("POST", "/studio/widgets", args))];
    case "delete_widget":
      await bridge("DELETE", `/studio/widgets?id=${encodeURIComponent(args.id)}`);
      return [text("Gelöscht.")];
    case "render_widget": {
      const { png, display } = await bridge("POST", "/studio/render", args);
      return [{ type: "image", data: png, mimeType: "image/png" }, text({ display })];
    }
    case "screenshot_simulator": {
      const folder = await mkdtemp(join(tmpdir(), "stand-shot-"));
      const file = join(folder, "shot.png");
      try {
        await run("xcrun", ["simctl", "io", args.device || "booted", "screenshot", file]);
        return [{ type: "image", data: (await readFile(file)).toString("base64"), mimeType: "image/png" }];
      } finally {
        await rm(folder, { recursive: true, force: true });
      }
    }
    default:
      throw new Error(`Unbekanntes Werkzeug ${name}`);
  }
}

function send(message) {
  process.stdout.write(JSON.stringify({ jsonrpc: "2.0", ...message }) + "\n");
}

async function handle(message) {
  const { id, method, params } = message;
  if (id === undefined) return;
  switch (method) {
    case "initialize":
      return send({ id, result: {
        protocolVersion: params?.protocolVersion || "2025-06-18",
        capabilities: { tools: {} },
        serverInfo: { name: "amberlight-widgets", version: "1.0.0" },
      } });
    case "ping":
      return send({ id, result: {} });
    case "tools/list":
      return send({ id, result: { tools } });
    case "tools/call":
      try {
        return send({ id, result: { content: await call(params.name, params.arguments) } });
      } catch (error) {
        return send({ id, result: { content: [text(String(error.message || error))], isError: true } });
      }
    default:
      return send({ id, error: { code: -32601, message: `Method not found: ${method}` } });
  }
}

createInterface({ input: process.stdin }).on("line", (line) => {
  if (!line.trim()) return;
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    return send({ id: null, error: { code: -32700, message: "Parse error" } });
  }
  handle(message);
});
