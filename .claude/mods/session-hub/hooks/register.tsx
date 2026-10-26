import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { Call, CallStatus, Hub } from '../types'

const PANE = 'session-hub'
const MAX_CALLS = 60
const MAX_EDITED_ROWS = 5
const SPIN_MS = 500
const SPINNER = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
const EDIT_TOOLS = new Set(['Edit', 'Write', 'MultiEdit', 'NotebookEdit'])

const EMPTY: Hub = {
  turnNo: 0,
  isWorking: false,
  turnStartedAt: 0,
  lastMs: null,
  calls: [],
  edited: [],
  failures: 0,
  inputTokens: 0,
  outputTokens: 0,
  cacheReadTokens: 0,
  cacheWriteTokens: 0,
}

const hub = atom({ plugin: 'session-hub', key: 'hub' } as const, EMPTY)
const isPaneOpen = atom({ plugin: 'session-hub', key: 'isPaneOpen' } as const, false)

const pad = (n: number): string => String(n).padStart(2, '0')
const mmss = (ms: number): string => {
  const s = Math.max(0, Math.floor(ms / 1000))
  return `${pad(Math.floor(s / 60))}:${pad(s % 60)}`
}
const fmtDur = (ms: number): string =>
  ms < 1000 ? `${Math.round(ms)}ms` : ms < 60_000 ? `${(ms / 1000).toFixed(1)}s` : mmss(ms)
const fmtTok = (n: number): string =>
  n >= 1000 ? `${(n / 1000).toFixed(1)}k` : String(n)
const tail = (p: string): string => p.split('/').slice(-2).join('/')
const oneLine = (s: string): string => s.replace(/\s+/g, ' ').trim()

// エンジンが付ける内部キー（ツール引数ではない）
const INTERNAL_KEYS = new Set(['tool', 'tool_use_id', 'agentId', 'requestMeta'])
const MAX_LABEL = 200

const str = (v: unknown): string => (typeof v === 'string' ? v : '')

// ツール名の表示名と内容（1行）を作る。MCP は「MCP server/tool」表記
const describe = (tool: string, e: Record<string, unknown>): { name: string; label: string } => {
  if (tool.startsWith('mcp__')) {
    const [, server = '', ...rest] = tool.split('__')
    const first = Object.entries(e).find(
      ([k, v]) => !INTERNAL_KEYS.has(k) && typeof v === 'string' && v !== '',
    )?.[1]
    return { name: `MCP ${server}/${rest.join('__')}`, label: oneLine(str(first)) }
  }
  const label =
    str(e.command) ||
    (e.file_path || e.notebook_path ? tail(str(e.file_path || e.notebook_path)) : '') ||
    str(e.pattern) ||
    str(e.description) ||
    str(e.url) ||
    str(e.query) ||
    str(e.skill) ||
    str(e.path)
  return { name: tool, label: oneLine(label) }
}

// 全入力トークン = 新規入力 + キャッシュ読み取り + キャッシュ書き込み
const totalIn = (h: Hub): number => h.inputTokens + h.cacheReadTokens + h.cacheWriteTokens
const cachePct = (h: Hub): number => {
  const total = totalIn(h)
  return total === 0 ? 0 : Math.round((h.cacheReadTokens / total) * 100)
}
const bar = (pct: number, cells = 10): string => {
  const fill = Math.round((pct / 100) * cells)
  return '█'.repeat(fill) + '░'.repeat(cells - fill)
}

// 端末の表示幅（全角=2桁）。帯を幅に合わせて取捨選択するために使う
const cellWidth = (text: string): number => {
  let w = 0
  for (const ch of text) {
    const c = ch.codePointAt(0) ?? 0
    const isWide =
      (c >= 0x1100 && c <= 0x115f) ||
      (c >= 0x2e80 && c <= 0xa4cf) ||
      (c >= 0xac00 && c <= 0xd7a3) ||
      (c >= 0xf900 && c <= 0xfaff) ||
      (c >= 0xfe30 && c <= 0xfe6f) ||
      (c >= 0xff00 && c <= 0xff60) ||
      (c >= 0xffe0 && c <= 0xffe6) ||
      (c >= 0x1f300 && c <= 0x1f64f) ||
      (c >= 0x20000 && c <= 0x3fffd)
    w += isWide ? 2 : 1
  }
  return w
}

// 幅 max に収まるよう、末尾を「…」で省略する
const fitText = (text: string, max: number): string => {
  if (cellWidth(text) <= max) return text
  let out = ''
  for (const ch of text) {
    if (cellWidth(out + ch) > max - 1) break
    out += ch
  }
  return `${out}…`
}

type Seg = { t: string; color?: string }
const segWidth = (segs: Seg[]): number => segs.reduce((n, x) => n + cellWidth(x.t), 0)
const SEP: Seg = { t: ' | ', color: 'inactive' }

const SYMBOL: Record<Exclude<CallStatus, 'running'>, string> = { ok: '✓', error: '✗', denied: '⊘' }

export const register: Register = on => {
  let timer: { cancel: () => void } | undefined

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'hud',
      description: 'セッションハブ（サイドパネル）を開く／閉じる',
    })
    // 初期表示: 幅が足りない画面では描画されず待機し、帯が代わりに出る
    void $.ui.open({ id: PANE, title: 'セッションハブ' }).catch(() => undefined)

    return next(e)
  })

  on('command.run', { command: 'hud' }, async $ => {
    // 開いていても幅不足で待機中（isPlaced=false）なら、閉じずに改めて開く
    const isShown = (await $.ui.panes()).some(p => p.id === PANE && p.isPlaced)

    if (isShown) {
      await $.ui.close({ id: PANE })
      return { text: 'セッションハブを閉じました' }
    }

    await $.ui.open({ id: PANE, title: 'セッションハブ' })
    return { text: 'セッションハブを開きました' }
  })

  on('ui.open', { id: PANE }, async ($, e, next) => {
    const opened = await next(e)
    await update($, isPaneOpen, () => opened.isPlaced)
    return opened
  }).catch(($, e, next) => next(e))

  on('ui.close', { id: PANE }, async ($, e, next) => {
    const done = await next(e)
    await update($, isPaneOpen, () => false)
    return done
  }).catch(($, e, next) => next(e))

  on('turn.start', async ($, e, next) => {
    const t = await $.clock.now()
    await update($, hub, s => ({ ...s, turnNo: s.turnNo + 1, isWorking: true, turnStartedAt: t }))
    timer?.cancel()
    timer = $.clock.every(SPIN_MS, () => $.ui.invalidate('ui.render'))

    return next(e)
  }).catch(($, e, next) => next(e))

  on('tool.call', async ($, e, next) => {
    const id = e.tool_use_id
    const startedAt = await $.clock.now()
    const { name, label } = describe(e.tool, e as unknown as Record<string, unknown>)
    const call: Call = {
      id,
      tool: name,
      label: label.slice(0, MAX_LABEL),
      status: 'running',
      isSub: e.agentId !== undefined,
      startedAt,
      durationMs: null,
    }
    await update($, hub, s => ({ ...s, calls: [...s.calls, call].slice(-MAX_CALLS) }))

    const ran = await next(e)
    const status: CallStatus =
      ran.deny !== undefined ? 'denied' : ran.isError === true ? 'error' : 'ok'
    const durationMs = (await $.clock.now()) - startedAt
    const args = e as unknown as Record<string, unknown>
    const file = str(args.file_path) || str(args.notebook_path)

    await update($, hub, s => {
      const isEdit = status === 'ok' && file !== '' && EDIT_TOOLS.has(e.tool)
      const known = s.edited.find(x => x.file === file)

      return {
        ...s,
        calls: s.calls.map(c => (c.id === id ? { ...c, status, durationMs } : c)),
        failures: s.failures + (status === 'ok' ? 0 : 1),
        edited: !isEdit
          ? s.edited
          : known
            ? s.edited.map(x =>
                x.file === file ? { ...x, tool: e.tool, count: x.count + 1 } : x,
              )
            : [...s.edited, { file, tool: e.tool, count: 1 }],
      }
    })

    return ran
  }).catch(($, e, next) => next(e))

  on('turn.complete', async ($, e, next) => {
    if (e.agentId !== undefined) {
      return next(e)
    }

    timer?.cancel()
    timer = undefined
    const u = e.usage
    const endedAt = await $.clock.now()
    await update($, hub, s => ({
      ...s,
      // 中断などで完了しなかったツールは、実行中のまま残さず失敗にする
      calls: s.calls.map(c =>
        c.status === 'running'
          ? { ...c, status: 'error' as const, durationMs: endedAt - c.startedAt }
          : c,
      ),
      failures: s.failures + s.calls.filter(c => c.status === 'running').length,
      isWorking: false,
      lastMs: e.durationMs,
      inputTokens: s.inputTokens + (u?.input_tokens ?? 0),
      outputTokens: s.outputTokens + (u?.output_tokens ?? 0),
      cacheReadTokens: s.cacheReadTokens + (u?.cache_read_input_tokens ?? 0),
      cacheWriteTokens: s.cacheWriteTokens + (u?.cache_creation_input_tokens ?? 0),
    }))

    return next(e)
  })

  // ---- 広い画面: サイドパネル ----
  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const s = await read($, hub)
    const now = await $.clock.now()
    const spin = SPINNER[Math.floor(now / SPIN_MS) % SPINNER.length]
    const pct = cachePct(s)
    const editedRows = Math.min(Math.max(s.edited.length, 1), MAX_EDITED_ROWS)
    const room = Math.max(3, (e.viewport?.rows ?? 24) - 11 - editedRows)

    return (
      <Box flexDirection="column">
        {s.isWorking ? (
          <Text bold color="warning" wrap="truncate-end">
            {spin} 実行中 {mmss(now - s.turnStartedAt)}　ターン #{s.turnNo}
          </Text>
        ) : (
          <Text bold color="success" wrap="truncate-end">
            ● 待機中 前回 {s.lastMs === null ? '--:--' : mmss(s.lastMs)}　ターン #{s.turnNo}
          </Text>
        )}
        <Text wrap="truncate-end">
          ツール {s.calls.length}　失敗{' '}
          <Text bold color={s.failures > 0 ? 'error' : undefined}>
            {s.failures}
          </Text>
          　編集 {s.edited.length} ファイル
        </Text>
        <Text wrap="truncate-end">
          トークン in {fmtTok(totalIn(s))} / out {fmtTok(s.outputTokens)}
        </Text>
        <Text wrap="truncate-end">
          キャッシュ {pct}% {bar(pct)}
        </Text>
        <Text> </Text>
        <Text bold>- ツール -</Text>
        {s.calls.length === 0 && <Text dimColor>（まだありません）</Text>}
        {s.calls.slice(-room).map(c => (
          <Text
            wrap="truncate-end"
            color={c.status === 'error' || c.status === 'denied' ? 'error' : undefined}
            dimColor={c.status === 'ok'}
          >
            {c.isSub ? '  └ ' : ''}
            {c.status === 'running' ? spin : SYMBOL[c.status]} {c.tool} {c.label}{' '}
            {c.durationMs === null ? mmss(now - c.startedAt) : fmtDur(c.durationMs)}
          </Text>
        ))}
        <Text> </Text>
        <Text bold>- 編集ファイル -</Text>
        {s.edited.length === 0 && <Text dimColor>（まだありません）</Text>}
        {s.edited.slice(-MAX_EDITED_ROWS).map(f => (
          <Text wrap="truncate-end">
            {f.tool} {f.file}
            {f.count > 1 ? ` ×${f.count}` : ''}
          </Text>
        ))}
      </Box>
    )
  })

  // ---- 狭い画面: 入力欄上の2行の帯（パネルが描画されている間は出さない） ----
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const s = await read($, hub)

    if (e.props.hasSurvey) {
      return next(e)
    }

    // パネルが実際に描画されている間は出さない（開いても幅不足で待機中なら出す）
    let isShown = await read($, isPaneOpen)
    try {
      isShown = (await $.ui.panes()).some(p => p.id === PANE && p.isPlaced)
    } catch {
      // 描画中に panes() が使えない場合は、ui.open の結果を使う
    }

    if (isShown) {
      return next(e)
    }

    const { Box, Text } = $.ui.resolve(e)
    const now = await $.clock.now()
    const width = Math.max(10, e.props.bodyColumns ?? 40)
    const spin = SPINNER[Math.floor(now / SPIN_MS) % SPINNER.length]
    const stateColor = s.isWorking ? 'warning' : 'success'
    const last1 = s.lastMs === null ? '--:--' : mmss(s.lastMs)
    // 状態は常にアイコン（待機中=●、実行中=スピナー）。文字は使わず幅を節約する
    const stateIcon: Seg = {
      t: s.isWorking ? `${spin} ${mmss(now - s.turnStartedAt)}` : `● 前回 ${last1}`,
      color: stateColor,
    }
    const stateBare: Seg = {
      t: s.isWorking ? `${spin} ${mmss(now - s.turnStartedAt)}` : '●',
      color: stateColor,
    }
    const turn: Seg = { t: ` #${s.turnNo}` }
    const tools: Seg = { t: `ツール ${s.calls.length}` }
    const fails: Seg = { t: ` 失敗 ${s.failures}`, color: s.failures > 0 ? 'error' : undefined }
    const edits: Seg = { t: ` 編集 ${s.edited.length}` }
    const tokens: Seg = { t: `in ${fmtTok(totalIn(s))} / out ${fmtTok(s.outputTokens)}` }
    const cache: Seg = { t: `cache ${cachePct(s)}%` }

    // 項目の多い順に試し、幅に収まる最初のものを使う
    const levels: { withTurn: boolean; body: Seg[] }[] = [
      { withTurn: true, body: [turn, SEP, tools, fails, edits, SEP, tokens, SEP, cache] },
      { withTurn: true, body: [turn, SEP, tools, fails, edits, SEP, tokens] },
      { withTurn: true, body: [turn, SEP, tools, fails, edits] },
      { withTurn: true, body: [turn, SEP, tools, fails] },
    ]
    const candidates: Seg[][] = [
      ...levels.map(l => [stateIcon, ...l.body]),
      [stateBare, SEP, tools, fails],
      [stateBare, SEP, tools],
      [stateBare],
    ]
    const line1 =
      candidates.find(c => segWidth(c) <= width) ?? [{ ...stateBare, t: fitText(stateBare.t, width) }]

    // 2行目は所要時間を右端に残し、ツール内容の途中を省略する
    const last = s.calls[s.calls.length - 1]
    let line2 = '（ツール呼び出しなし）'
    if (last) {
      const dur = last.durationMs === null ? mmss(now - last.startedAt) : fmtDur(last.durationMs)
      const mark = last.status === 'running' ? spin : SYMBOL[last.status]
      const head = `${mark} ${last.tool}`
      const room = width - cellWidth(head) - cellWidth(dur) - 2
      line2 =
        room >= 2
          ? `${head} ${fitText(last.label, room)} ${dur}`.replace(/\s{2,}/g, ' ')
          : fitText(`${head} ${dur}`, width)
    }

    return (
      <Box flexDirection="column">
        <Text wrap="truncate-end" bold>
          {line1.map(x => (
            <Text color={x.color}>{x.t}</Text>
          ))}
        </Text>
        <Text wrap="truncate-end" dimColor>
          {fitText(line2, width)}
        </Text>
      </Box>
    )
  })
}
