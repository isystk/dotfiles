import type { Register } from 'claude-code'

type Level = 'low' | 'medium' | 'high' | 'xhigh'

const LEVELS: readonly Level[] = ['low', 'medium', 'high', 'xhigh']
// plan 付きは「Plan Mode に入るべき依頼」（設計・複数ファイルに及ぶ変更など）
const LABELS = [...LEVELS, 'high plan', 'xhigh plan'] as const
const MAX_STEPS = 10 // これを超えるモデル往復で1段上げる
const MAX_ERRORS = 2 // ツールエラーがこの回数に達したら1段上げる
const HEAD = 600
const TAIL = 200
const ACK_MAX = 20

// effort を変えてもプロンプトキャッシュが保たれるモデルのみ対象（Opus/Sonnet 5.5+、Fable 5.1+）
const isSupported = (model: string): boolean => {
  const m = /(opus|sonnet|fable)-(\d+)(?:-(\d+))?/.exec(model)
  if (!m) return false
  const major = Number(m[2])
  const minor = Number(m[3] ?? 0)
  return m[1] === 'fable' ? major > 5 || (major === 5 && minor >= 1) : major > 5 || (major === 5 && minor >= 5)
}

// 20文字未満の同意だけの入力（OK / はい / 続けて 等）
const ACK = /^(ok|okay|はい|うん|お願い(します)?|続けて|進めて|どうぞ|了解|やって|それで|いいよ|いいね|go|yes|y)[\s!！。.]*$/i

const CRITERIA = `あなたは依頼の難しさ判定器。作業量ではなく「作業内容の不確実性」と「見落としたときの損の大きさ」で判定する。
low: 雑談・確認・コミット・手順が決まっている機械的な修正
medium: 決めた方針の実装・テスト追加・コード説明・調べもの
high: 不具合の原因調査・設計案の比較・差分のレビュー
xhigh: 全体の監査や移行・並行処理/セキュリティ/データ消失に関わる作業
high / xhigh のうち、実装前に設計・方針の合意が要る依頼（新機能・複数ファイルに及ぶ変更・全面的な作り直し・移行）は末尾に " plan" を付ける（例: "high plan"）。調査・レビュー・説明・小さな修正には付けない。
以下の依頼を判定せよ。`

// コードブロックは行数だけの印にして、冒頭と末尾だけ渡す
const shrink = (text: string): string => {
  const t = text.replace(/```[\s\S]*?```/g, m => `[コードブロック ${m.split('\n').length} 行]`)
  return t.length <= HEAD + TAIL ? t : `${t.slice(0, HEAD)}\n…\n${t.slice(-TAIL)}`
}

// 判定ラベルを段階と plan 指定に分ける
export const parseVerdict = (v: string | undefined): { level: Level; plan: boolean } | undefined => {
  const [l, p] = (v ?? '').trim().split(/\s+/)
  const level = LEVELS.find(x => x === l)
  if (!level) return undefined
  return { level, plan: p === 'plan' && (level === 'high' || level === 'xhigh') }
}

const bump = (l: Level): Level => LEVELS[Math.min(LEVELS.indexOf(l) + 1, LEVELS.length - 1)] ?? l

export const register: Register = (on, _options) => {
  let enabled = true
  let planEnabled = true // Plan Mode の自動切替
  let justPlanned = false // 直前のターンで切り替えた（承認後の再突入を防ぐ）
  let lastLevel: Level | undefined // 前のターンの最終段階（同意の引き継ぎ用）
  let cur: { turnId: string; level: Level; errors: number; bumped: boolean } | undefined
  const log: { at: number; level: Level; text: string }[] = []

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'effort-router',
      description: 'effort 自動判定の on/off と判定ログ（引数: on | off | plan on | plan off | log）',
    })
    return next(e)
  })

  on('command.run', { command: 'effort-router' }, async (_$, e) => {
    const arg = String((e as { args?: string }).args ?? '').trim()
    if (arg === 'on' || arg === 'off') {
      enabled = arg === 'on'
      return { text: `effort-router: ${arg}` }
    }
    if (arg === 'plan on' || arg === 'plan off') {
      planEnabled = arg === 'plan on'
      return { text: `effort-router plan: ${arg.slice(5)}` }
    }
    if (arg === 'log') {
      const count = LEVELS.map(l => `${l}=${log.filter(x => x.level === l).length}`).join(' ')
      const recent = log.slice(-10).map(x => `${x.level}  ${x.text.replace(/\s+/g, ' ').slice(0, 40)}`)
      return { text: [`ターン数: ${count}`, ...recent].join('\n') }
    }
    return { text: `effort-router: ${enabled ? 'on' : 'off'}（plan: ${planEnabled ? 'on' : 'off'}、引数: on | off | plan on | plan off | log）` }
  })

  on('turn.start', async ($, e, next) => {
    if (!enabled) {
      cur = undefined
      return next(e)
    }
    const text = e.text.trim()
    let level: Level | undefined
    let plan = false

    if (text === '') {
      level = lastLevel // 継続ターン等は前の段階を引き継ぐ
    } else if (text.length < ACK_MAX && ACK.test(text)) {
      level = lastLevel
    } else {
      try {
        const res = await $.model.classify(`${CRITERIA}\n\n依頼:\n${shrink(text)}`, LABELS, { model: 'haiku' })
        const v = parseVerdict(res as string | undefined)
        level = v?.level ?? lastLevel
        plan = v?.plan ?? false
      } catch {
        level = undefined // 判定失敗時は組み込みの effort のまま
      }
    }

    cur = level ? { turnId: e.turnId, level, errors: 0, bumped: false } : undefined
    const enter = plan && planEnabled && !justPlanned && e.agentId === undefined
    justPlanned = false
    if (level) {
      log.push({ at: Date.now(), level, text })
      $.ui.status(enter ? `${level} plan` : `${level}`)
    }
    if (enter) {
      try {
        await $.tool.call({ tool: 'EnterPlanMode' })
        justPlanned = true
      } catch {
        // 切替に失敗してもターンは止めない
      }
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  on('tool.call', async ($, e, next) => {
    const ran = await next(e)
    if (ran.isError === true && e.agentId === undefined && cur) cur.errors += 1
    return ran
  }).catch(($, e, next) => next(e))

  on('turn.step', async function* ($, e, next) {
    if (!enabled || e.effort === undefined || !isSupported(e.model)) {
      return yield* next(e)
    }
    // サブエージェント: 親ターンの段階を継承する（判定・引き上げ・状態更新はしない）
    // turnId は親と別なので照合せず、バックグラウンドで親ターン終了後に動く場合は lastLevel へフォールバックする
    if (e.agentId !== undefined) {
      const inherited = cur?.level ?? lastLevel
      return yield* next(inherited ? { ...e, effort: inherited } : e)
    }
    // メインスレッド
    if (!cur || cur.turnId !== e.turnId) {
      return yield* next(e)
    }
    if (!cur.bumped && (e.index > MAX_STEPS || cur.errors >= MAX_ERRORS)) {
      cur.level = bump(cur.level)
      cur.bumped = true
      $.ui.status(`${cur.level}（引き上げ）`)
    }
    lastLevel = cur.level
    const last = log[log.length - 1]
    if (last) last.level = cur.level // 最終段階で記録する
    return yield* next({ ...e, effort: cur.level })
  })
}
