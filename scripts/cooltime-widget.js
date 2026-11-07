// Cooltime のウィジェット（Scriptable 用）。Cooltime が、iCloud の Scriptable フォルダに書き出した
// cooltime-status.json を読んで、残りと戻る時刻を出す。通信はしない。
// 使い方: ホーム画面を長押し → ＋ → Scriptable → ウィジェットを追加 → 長押しして編集 → Script で「Cooltime」を選ぶ。

const FILE = "cooltime-status.json"
const STALE_MIN = 30   // これより古い情報は、古いと分かるように出す

const dyn = (light, dark) => Color.dynamic(new Color(light), new Color(dark))
const C = {
  bg: dyn("#f2f2f7", "#1c1c1e"),
  text: dyn("#1c1c1e", "#f2f2f7"),
  sub: dyn("#5c5c62", "#b4b4bb"),
  track: dyn("#d0d0d6", "#3a3a3f"),
  fill: dyn("#1a5fd1", "#6aa4ff"),
  warn: dyn("#a8320a", "#ff9f80"),
}

function clock(sec) {
  const d = new Date(sec * 1000)
  const t = new Intl.DateTimeFormat("ja-JP", { hour: "2-digit", minute: "2-digit", hour12: false }).format(d)
  const same = d.toDateString() === new Date().toDateString()
  return same ? t : `${d.getMonth() + 1}/${d.getDate()} ${t}`
}

function remainingText(sec) {
  const m = Math.max(1, Math.ceil((sec * 1000 - Date.now()) / 60000))
  if (m < 60) return `あと${m}分`
  if (m < 1440) return m % 60 === 0 ? `あと${m / 60}時間` : `あと${Math.floor(m / 60)}時間${m % 60}分`
  return `あと${Math.floor(m / 1440)}日`
}

async function load() {
  const fm = FileManager.iCloud()
  const path = fm.joinPath(fm.documentsDirectory(), FILE)
  if (!fm.fileExists(path)) return null
  if (!fm.isFileDownloaded(path)) await fm.downloadFileFromiCloud(path)
  try { return JSON.parse(fm.readString(path)) } catch (e) { return null }
}

function addBar(parent, percent) {
  const w = 120, h = 6
  const ctx = new DrawContext()
  ctx.size = new Size(w, h)
  ctx.opaque = false
  ctx.respectScreenScale = true
  ctx.setFillColor(C.track)
  const base = new Path(); base.addRoundedRect(new Rect(0, 0, w, h), 3, 3)
  ctx.addPath(base); ctx.fillPath()
  if (percent > 0) {
    ctx.setFillColor(C.fill)
    const p = new Path(); p.addRoundedRect(new Rect(0, 0, Math.max(h, w * percent / 100), h), 3, 3)
    ctx.addPath(p); ctx.fillPath()
  }
  const img = parent.addImage(ctx.getImage())
  img.imageSize = new Size(w, h)
}

function addEntry(parent, e, compact) {
  const row = parent.addStack()
  row.layoutVertically()
  const head = row.addStack()
  head.centerAlignContent()
  const name = head.addText(e.title)
  name.font = Font.semiboldSystemFont(compact ? 12 : 13)
  name.textColor = C.text
  name.lineLimit = 1
  head.addSpacer()
  let badge, color = C.text
  if (e.state === "limited") badge = `制限中 ${remainingText(e.until)}`
  else if (e.state === "available") badge = "使用可能"
  else badge = "未確認"
  const b = head.addText(badge)
  b.font = Font.boldSystemFont(compact ? 11 : 12)
  b.textColor = e.state === "limited" ? C.warn : color

  if (e.state === "limited") {
    const t = row.addText(`${clock(e.until)} に戻ります`)
    t.font = Font.systemFont(10); t.textColor = C.sub
  }
  const wins = (e.windows || []).filter(w => w.remainingPercent !== undefined).slice(0, compact ? 1 : 2)
  for (const w of wins) {
    const line = row.addStack()
    const label = line.addText(`${w.label}  ${w.exhausted ? "尽きた" : "残り " + w.remainingPercent + "%"}`)
    label.font = Font.systemFont(10); label.textColor = C.sub
    line.addSpacer()
    if (w.resetsAt) { const r = line.addText(`${clock(w.resetsAt)} リセット`); r.font = Font.systemFont(10); r.textColor = C.sub }
    addBar(row, w.remainingPercent)
  }
  if (e.credit) {
    const t = row.addText(`残高 ${e.credit}`); t.font = Font.systemFont(10); t.textColor = C.sub
  }
  if (e.failed) {
    const t = row.addText("取得に失敗（数字は古い）"); t.font = Font.boldSystemFont(10); t.textColor = C.warn
  }
}

const widget = new ListWidget()
widget.backgroundColor = C.bg
widget.setPadding(12, 14, 12, 14)
widget.refreshAfterDate = new Date(Date.now() + 5 * 60 * 1000)
const family = config.widgetFamily || "medium"
const compact = family === "small"

const data = await load()
if (!data) {
  const t = widget.addText("Cooltime のデータが見つかりません。Mac の Cooltime で「スマホのウィジェット」をオンにしてください。")
  t.font = Font.systemFont(12); t.textColor = C.text
} else {
  const header = widget.addStack()
  header.centerAlignContent()
  const ageMin = Math.floor((Date.now() / 1000 - data.generatedAt) / 60)
  const h = header.addText(`Cooltime ${clock(data.generatedAt)} 時点`)
  h.font = Font.boldSystemFont(12); h.textColor = C.sub
  if (ageMin >= STALE_MIN) {
    header.addSpacer()
    const s = header.addText("古い情報")
    s.font = Font.boldSystemFont(11); s.textColor = C.warn
  }
  widget.addSpacer(6)
  const rank = e => (e.state === "limited" ? 0 : e.state === "available" ? 1 : 2)
  const entries = [...data.entries].sort((a, b) => rank(a) - rank(b) || (a.until || 0) - (b.until || 0))
  const max = family === "small" ? 1 : family === "medium" ? 2 : 5
  entries.slice(0, max).forEach((e, i) => { if (i) widget.addSpacer(8); addEntry(widget, e, compact) })
  if (entries.length > max) {
    widget.addSpacer(4)
    const more = widget.addText(`ほか ${entries.length - max} 件`)
    more.font = Font.systemFont(10); more.textColor = C.sub
  }
}

if (config.runsInWidget) Script.setWidget(widget)
else await widget.presentLarge()
Script.complete()
