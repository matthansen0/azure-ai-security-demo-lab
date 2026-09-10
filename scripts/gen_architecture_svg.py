"""Generate architecture SVG from the Excalidraw diagram data."""
import json

SVG_WIDTH = 1560
SVG_HEIGHT = 840

# Read excalidraw file for element positions (we'll render a clean SVG version)
elements_data = json.load(open("docs/architecture/azure-ai-security-sandbox-architecture.excalidraw"))

svg_parts = []
svg_parts.append(f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="-10 -10 {SVG_WIDTH} {SVG_HEIGHT}" width="{SVG_WIDTH}" height="{SVG_HEIGHT}" font-family="Segoe UI, -apple-system, sans-serif">
  <defs>
    <marker id="arrowhead" markerWidth="10" markerHeight="7" refX="10" refY="3.5" orient="auto">
      <polygon points="0 0, 10 3.5, 0 7" fill="#1e1e1e"/>
    </marker>
    <marker id="arrowhead-gray" markerWidth="10" markerHeight="7" refX="10" refY="3.5" orient="auto">
      <polygon points="0 0, 10 3.5, 0 7" fill="#757575"/>
    </marker>
    <marker id="arrowhead-amber" markerWidth="10" markerHeight="7" refX="10" refY="3.5" orient="auto">
      <polygon points="0 0, 10 3.5, 0 7" fill="#f59e0b"/>
    </marker>
  </defs>
  <rect x="-10" y="-10" width="{SVG_WIDTH}" height="{SVG_HEIGHT}" fill="white"/>
''')

def rect(x, y, w, h, fill, stroke, sw=2, opacity=1, dash="", rx=12):
    style = f'fill="{fill}" stroke="{stroke}" stroke-width="{sw}" rx="{rx}" opacity="{opacity}"'
    if dash:
        style += f' stroke-dasharray="{dash}"'
    return f'  <rect x="{x}" y="{y}" width="{w}" height="{h}" {style}/>'

def text(x, y, txt, size=20, color="#1e1e1e", anchor="middle", weight="normal"):
    return f'  <text x="{x}" y="{y}" font-size="{size}" fill="{color}" text-anchor="{anchor}" font-weight="{weight}">{txt}</text>'

def arrow(x1, y1, x2, y2, color="#1e1e1e", dash="", marker="arrowhead"):
    style = f'stroke="{color}" stroke-width="2" fill="none" marker-end="url(#{marker})"'
    if dash:
        style += f' stroke-dasharray="{dash}"'
    return f'  <line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" {style}/>'

def polyarrow(points, color="#1e1e1e", dash="", marker="arrowhead"):
    pts = " ".join(f"{x},{y}" for x, y in points)
    style = f'stroke="{color}" stroke-width="2" fill="none" marker-end="url(#{marker})"'
    if dash:
        style += f' stroke-dasharray="{dash}"'
    return f'  <polyline points="{pts}" {style}/>'

def label_on_line(x1, y1, x2, y2, txt, size=16, color="#1e1e1e", offset=-12):
    mx, my = (x1+x2)/2, (y1+y2)/2 + offset
    return f'  <text x="{mx}" y="{my}" font-size="{size}" fill="{color}" text-anchor="middle">{txt}</text>'

# === Title ===
svg_parts.append(text(390, 30, "Azure AI Security Sandbox", 28, "#1e1e1e", "start", "bold"))
svg_parts.append(text(390, 55, "Security-focused Azure OpenAI RAG architecture", 16, "#757575", "start"))

# === Security pills ===
pills = [
    (830, 8, 150, "#ffc9c9", "#ef4444", "WAF at edge"),
    (995, 8, 210, "#b2f2bb", "#22c55e", "Managed Identity"),
    (1220, 8, 100, "#d0bfff", "#8b5cf6", "RBAC"),
    (1335, 8, 160, "#eebefa", "#ec4899", "Observability"),
]
for px, py, pw, pfill, pstroke, ptxt in pills:
    svg_parts.append(rect(px, py, pw, 38, pfill, pstroke, 1, rx=19))
    svg_parts.append(text(px + pw/2, py + 24, ptxt, 16, "#1e1e1e"))

# === Zone 1: Main Runtime Flow ===
svg_parts.append(rect(20, 80, 1480, 240, "#dbe4ff", "#4a9eed", 2, 0.3))
svg_parts.append(text(55, 105, "Main Runtime Flow", 20, "#2563eb", "start", "bold"))

# Boxes
boxes = [
    (40, 150, 160, 80, "#a5d8ff", "#4a9eed", ["User", "(Chat UI)"]),
    (270, 140, 180, 100, "#ffc9c9", "#ef4444", ["Front Door", "+ WAF"]),
    (520, 140, 180, 100, "#d0bfff", "#8b5cf6", ["RAG App", "(Container Apps)"]),
    (770, 150, 180, 80, "#ffd8a8", "#f59e0b", ["API Management", "(AI Gateway)"]),
    (1020, 150, 180, 80, "#a5d8ff", "#4a9eed", ["Azure OpenAI", "(GPT-4o)"]),
    (1270, 150, 170, 80, "#c3fae8", "#22c55e", ["Cosmos DB", "(chat history)"]),
]
for bx, by, bw, bh, bfill, bstroke, lines in boxes:
    svg_parts.append(rect(bx, by, bw, bh, bfill, bstroke))
    cy = by + bh/2 - (len(lines)-1)*12
    for i, line in enumerate(lines):
        weight = "bold" if i == 0 else "normal"
        size = 18 if i == 0 else 15
        svg_parts.append(text(bx + bw/2, cy + i*24, line, size, "#1e1e1e", weight=weight))

# Runtime arrows
runtime_arrows = [
    (200, 190, 270, 190, "HTTPS"),
    (450, 190, 520, 190, "origin"),
    (700, 190, 770, 190, "SDK"),
    (950, 190, 1020, 190, "managed ID"),
]
for x1, y1, x2, y2, lbl in runtime_arrows:
    svg_parts.append(arrow(x1, y1, x2, y2))
    svg_parts.append(label_on_line(x1, y1, x2, y2, lbl, 14))

# Chat history arrow (curved over top)
svg_parts.append(polyarrow([(610, 140), (610, 110), (1355, 110), (1355, 150)]))
svg_parts.append(text(980, 102, "chat history", 14))

# === Zone 2: Data & Infrastructure ===
svg_parts.append(rect(20, 340, 1480, 190, "#d3f9d8", "#22c55e", 2, 0.3))
svg_parts.append(text(55, 365, "Data & Infrastructure", 20, "#15803d", "start", "bold"))

data_boxes = [
    (180, 400, 210, 80, "#d0bfff", "#8b5cf6", ["Container Registry"]),
    (620, 400, 200, 80, "#a5d8ff", "#4a9eed", ["AI Search"]),
    (1080, 400, 200, 80, "#c3fae8", "#22c55e", ["Azure Storage"]),
]
for bx, by, bw, bh, bfill, bstroke, lines in data_boxes:
    svg_parts.append(rect(bx, by, bw, bh, bfill, bstroke))
    svg_parts.append(text(bx + bw/2, by + bh/2 + 7, lines[0], 18, "#1e1e1e", weight="bold"))

# Data arrows from RAG App
svg_parts.append(polyarrow([(560, 240), (560, 370), (285, 400)], "#757575", "8,4", "arrowhead-gray"))
svg_parts.append(text(400, 360, "image pull", 14, "#757575"))

svg_parts.append(polyarrow([(620, 240), (720, 400)], "#1e1e1e"))
svg_parts.append(text(650, 325, "retrieval", 14))

svg_parts.append(polyarrow([(680, 240), (1180, 400)], "#1e1e1e"))
svg_parts.append(text(960, 310, "docs + citations", 14))

# Search to Storage
svg_parts.append(arrow(820, 440, 1080, 440, "#757575", "8,4", "arrowhead-gray"))
svg_parts.append(text(950, 430, "prepdocs", 14, "#757575"))

# === Zone 3: IT Admin Agent Path ===
svg_parts.append(rect(20, 550, 720, 210, "#fff3bf", "#f59e0b", 2, 0.3, "10,6"))
svg_parts.append(text(55, 575, "IT Admin Agent Path", 20, "#b45309", "start", "bold"))
svg_parts.append(text(330, 575, "(always deployed)", 16, "#b45309", "start"))

agent_boxes = [
    (40, 615, 200, 80, "#fff3bf", "#f59e0b", ["IT Admin Agent", "(FastAPI)"], True),
    (310, 615, 200, 80, "#eebefa", "#ec4899", ["AI Foundry", "(Account + Project)"], True),
    (580, 615, 140, 80, "#ffc9c9", "#ef4444", ["Key Vault"], True),
]
for bx, by, bw, bh, bfill, bstroke, lines, dashed in agent_boxes:
    svg_parts.append(rect(bx, by, bw, bh, bfill, bstroke, dash="8,4" if dashed else ""))
    cy = by + bh/2 - (len(lines)-1)*12 + 5
    for i, line in enumerate(lines):
        weight = "bold" if i == 0 else "normal"
        size = 17 if i == 0 else 14
        svg_parts.append(text(bx + bw/2, cy + i*22, line, size, "#1e1e1e", weight=weight))

# Agent arrows
svg_parts.append(arrow(240, 655, 310, 655, "#f59e0b", "8,4", "arrowhead-amber"))
svg_parts.append(text(275, 643, "project", 14, "#f59e0b"))
svg_parts.append(arrow(510, 655, 580, 655, "#f59e0b", "8,4", "arrowhead-amber"))
svg_parts.append(text(545, 643, "secrets", 14, "#f59e0b"))

# Agent to OpenAI (diagonal)
svg_parts.append(polyarrow([(140, 615), (1110, 230)], "#f59e0b", "8,4", "arrowhead-amber"))
svg_parts.append(text(580, 400, "model calls", 14, "#f59e0b"))

# === Zone 4: Monitoring ===
svg_parts.append(rect(780, 550, 720, 210, "#e5dbff", "#8b5cf6", 2, 0.3))
svg_parts.append(text(815, 575, "Monitoring & Diagnostics", 20, "#6d28d9", "start", "bold"))

monitor_boxes = [
    (830, 615, 220, 80, "#eebefa", "#ec4899", ["Application Insights"]),
    (1190, 615, 220, 80, "#d0bfff", "#8b5cf6", ["Log Analytics"]),
]
for bx, by, bw, bh, bfill, bstroke, lines in monitor_boxes:
    svg_parts.append(rect(bx, by, bw, bh, bfill, bstroke))
    svg_parts.append(text(bx + bw/2, by + bh/2 + 7, lines[0], 18, "#1e1e1e", weight="bold"))

# Telemetry arrows
svg_parts.append(polyarrow([(665, 240), (940, 615)], "#757575", "8,4", "arrowhead-gray"))
svg_parts.append(text(760, 440, "telemetry", 13, "#757575"))

svg_parts.append(polyarrow([(860, 230), (1300, 615)], "#757575", "8,4", "arrowhead-gray"))
svg_parts.append(text(1110, 410, "diagnostics", 13, "#757575"))

# === Legend ===
svg_parts.append(arrow(70, 790, 120, 790))
svg_parts.append(text(195, 795, "Runtime flow", 16, "#1e1e1e"))

svg_parts.append(arrow(340, 790, 390, 790, "#757575", "8,4", "arrowhead-gray"))
svg_parts.append(text(465, 795, "Deploy / infra", 16, "#757575"))

svg_parts.append(arrow(610, 790, 660, 790, "#f59e0b", "8,4", "arrowhead-amber"))
svg_parts.append(text(735, 795, "Agent path", 16, "#f59e0b"))

svg_parts.append("</svg>")

svg_content = "\n".join(svg_parts)
with open("docs/architecture/architecture.svg", "w") as f:
    f.write(svg_content)

print(f"Generated SVG: {len(svg_content)} bytes")
