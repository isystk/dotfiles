import { expect, test } from 'claude-code/testing'

const PANE_PROPS = {
  requestId: 'session-hub',
  title: 'セッションハブ',
  isFocused: false,
  bodyColumns: 60,
  placement: 'dock',
} as never

// 帯の「行」（入れ子の色分け Text は数えない）
const rows = async (ui: { findAll: (q: { type: string }) => Promise<{ props?: Record<string, unknown> }[]> }) =>
  (await ui.findAll({ type: 'Text' })).filter(x => x.props?.wrap === 'truncate-end')

const BAND_PROPS = {
  hasSurvey: false,
  isWorking: false,
  maxRows: 5,
  bodyColumns: 80,
} as never


test('ツール呼び出しがパネルに表示され、失敗数と編集ファイルが正しい', async ($, on) => {
  on('clock.now', () => ({ value: 1_000_000 }) as never)
  on('tool.call', (_$, e) =>
    e.tool === 'Bash' && e.command === 'false'
      ? { result: 'exit 1', isError: true }
      : { result: 'ok', isError: false },
  )

  await $.tool.call({ tool: 'Bash', command: 'echo ok' })
  await $.tool.call({ tool: 'Bash', command: 'false' })
  await $.tool.call({ tool: 'Edit', file_path: '/tmp/a.md', old_string: 'a', new_string: 'b' })
  await $.tool.call({ tool: 'Edit', file_path: '/tmp/b.md', old_string: 'a', new_string: 'b' })

  const ui = await $.ui.mount({
    plugin: 'session-hub',
    surface: 'terminal',
    component: 'Pane',
    requestId: 'session-hub',
    props: PANE_PROPS,
  })

  expect(await ui.find({ type: 'Text', text: /ツール 4.*失敗\s*1.*編集 2 ファイル/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /待機中/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '- ツール -' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '- 編集ファイル -' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /✗ Bash false/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Edit \/tmp\/a\.md/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Edit \/tmp\/b\.md/ })).toBeDefined()
})

test('/hud を2回実行すると 開く → 閉じる と切り替わる', async ($, on) => {
  const open = new Set<string>()

  on('ui.open', (_$, e) => {
    open.add(e.id)
    return { value: { isPlaced: true as const } }
  })
  on('ui.close', (_$, e) => {
    open.delete(e.id)
    return { value: undefined }
  })
  on('ui.panes', () => ({
    value: [...open].map(id => ({
      id,
      title: id,
      isShown: true,
      isFocused: false,
      isPlaced: true,
    })),
  }))

  const first = await $.command.run({ command: 'hud' })
  expect(first.text).toContain('開きました')
  expect(open.has('session-hub')).toBe(true)

  const second = await $.command.run({ command: 'hud' })
  expect(second.text).toContain('閉じました')
  expect(open.has('session-hub')).toBe(false)
})

test('狭い画面の帯は2行（要約＋直近ツール1件）で、パネル表示中は出ない', async ($, on) => {
  on('clock.now', () => ({ value: 1_000_000 }) as never)
  on('tool.call', () => ({ result: 'ok', isError: false }))
  const open = new Set<string>()
  on('ui.open', (_$, e) => {
    open.add(e.id)
    return { value: { isPlaced: true as const } }
  })
  on('ui.panes', () => ({
    value: [...open].map(id => ({ id, title: id, isShown: true, isFocused: false, isPlaced: true })),
  }))
  on('ui.render', () => ({ type: 'Box' }) as never)
  on('turn.start', (_$, e) => e as never)
  on('clock.every', () => ({ value: undefined }) as never)

  await $.tool.call({ tool: 'Bash', command: 'echo one' })
  await $.tool.call({ tool: 'Bash', command: 'echo two' })

  const band = await $.ui.mount({
    plugin: 'session-hub',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: BAND_PROPS,
  })

  // 起動直後（ターン #0）から帯が出る
  expect(await rows(band)).toHaveLength(2)
  expect(await band.find({ type: 'Text', text: /^● 前回.*#0/ })).toBeDefined()
  await $.turn.start({ text: 'hello', turnId: 't0' })
  await band.redraw()

  expect(await rows(band)).toHaveLength(2)
  expect(await band.find({ type: 'Text', text: /ツール 2 失敗 0 編集 0/ })).toBeDefined()
  expect(await band.find({ type: 'Text', text: /✓ Bash echo two/ })).toBeDefined()

  await $.command.run({ command: 'hud' })
  await band.redraw()
  expect(await rows(band)).toHaveLength(0)
})

test('起動時（session.start）にパネルが自動で開く', async ($, on) => {
  const opened: string[] = []
  on('ui.open', (_$, e) => {
    opened.push(e.id)
    return { value: { isPlaced: true as const } }
  })

  on('command.register', () => ({ value: undefined }) as never)
  on('session.start', (_$, e) => e as never)

  await $.session.start({ source: 'startup', cwd: '/tmp' } as never)

  expect(opened).toContain('session-hub')
})

test('帯は幅に応じて項目を減らし、2行目は所要時間を残す', async ($, on) => {
  on('clock.now', () => ({ value: 1_000_000 }) as never)
  on('tool.call', () => ({ result: 'ok', isError: false }))
  on('ui.panes', () => ({ value: [] }))
  on('ui.render', () => ({ type: 'Box' }) as never)

  await $.tool.call({ tool: 'Bash', command: 'echo a-very-long-command-line --with --many --flags' })

  const mountAt = async (bodyColumns: number) =>
    $.ui.mount({
      plugin: 'session-hub',
      surface: 'terminal',
      component: 'AbovePrompt',
      props: { hasSurvey: false, isWorking: false, maxRows: 5, bodyColumns } as never,
    })

  const wide = await mountAt(100)
  expect(await wide.find({ type: 'Text', text: /in 0 \/ out 0 \| cache 0%/ })).toBeDefined()
  expect(await wide.find({ type: 'Text', text: /待機中|実行中/ })).toBeUndefined()

  const mid = await mountAt(40)
  expect(await mid.find({ type: 'Text', text: /cache/ })).toBeUndefined()
  expect(await mid.find({ type: 'Text', text: /ツール 1 失敗 0/ })).toBeDefined()
  expect(await mid.find({ type: 'Text', text: /…\s0ms$/ })).toBeDefined()

  // 状態は常にアイコン（「待機中」の文字は出さない）
  const icon = await mountAt(58)
  expect(await icon.find({ type: 'Text', text: /in 0 \/ out 0/ })).toBeDefined()
  expect(await icon.find({ type: 'Text', text: /待機中/ })).toBeUndefined()
  expect(await icon.find({ type: 'Text', text: /^● 前回/ })).toBeDefined()

  const tiny = await mountAt(8)
  expect(await tiny.find({ type: 'Text', text: /ツール/ })).toBeUndefined()
  expect(await tiny.find({ type: 'Text', text: '●' })).toBeDefined()
})

test('in は全入力（新規＋キャッシュ読み取り＋書き込み）で、cache は読み取りの割合', async ($, on) => {
  on('clock.now', () => ({ value: 1_000_000 }) as never)
  on('turn.complete', () => ({ text: '' }))

  await $.turn.complete({
    answer: '',
    durationMs: 1000,
    isAborted: false,
    turnId: 't1',
    reason: 'answer',
    usage: {
      input_tokens: 4,
      output_tokens: 4500,
      cache_read_input_tokens: 90_000,
      cache_creation_input_tokens: 5_000,
      model: 'test',
    },
  } as never)

  const ui = await $.ui.mount({
    plugin: 'session-hub',
    surface: 'terminal',
    component: 'Pane',
    requestId: 'session-hub',
    props: PANE_PROPS,
  })

  expect(await ui.find({ type: 'Text', text: /in 95\.0k \/ out 4\.5k/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /キャッシュ 95%/ })).toBeDefined()
})

test('拒否は ⊘、MCP は「MCP サーバー/ツール 引数」表記で、内部キーは内容に出ない', async ($, on) => {
  on('clock.now', () => ({ value: 1_000_000 }) as never)
  on('tool.call', (_$, e) =>
    e.tool === 'Bash' ? { deny: 'blocked' } : { result: 'ok', isError: false },
  )

  await $.tool.call({ tool: 'Bash', command: 'echo denied-one' })
  await $.tool.call({ tool: 'mcp__context7__query-docs', agentId: 'agent-9', libraryId: '/x/y' } as never)

  const ui = await $.ui.mount({
    plugin: 'session-hub',
    surface: 'terminal',
    component: 'Pane',
    requestId: 'session-hub',
    props: PANE_PROPS,
  })

  expect(await ui.find({ type: 'Text', text: /⊘ Bash echo denied-one/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /└ ✓ MCP context7\/query-docs \/x\/y/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /agent-9/ })).toBeUndefined()
})

test('/hud は、開いているが幅不足で待機中のパネルを閉じず、開く', async ($, on) => {
  const opened: string[] = []
  on('ui.panes', () => ({
    value: [{ id: 'session-hub', title: 'x', isShown: false, isFocused: false, isPlaced: false }],
  }))
  on('ui.open', (_$, e) => {
    opened.push(e.id)
    return { value: { isPlaced: true as const } }
  })
  on('ui.close', () => ({ value: undefined }))

  const r = await $.command.run({ command: 'hud' })

  expect(r.text).toContain('開きました')
  expect(opened).toEqual(['session-hub'])
})

test('完了しないままターンが終わったツールは、実行中のまま残らず失敗になる', async ($, on) => {
  on('clock.now', () => ({ value: 1_000_000 }) as never)
  on('tool.call', () => new Promise(() => undefined) as never)
  on('turn.complete', () => ({ text: '' }))

  void $.tool.call({ tool: 'Bash', command: 'sleep 999' })
  await $.turn.complete({
    answer: '',
    durationMs: 1000,
    isAborted: true,
    turnId: 't1',
    reason: 'aborted',
  } as never)

  const ui = await $.ui.mount({
    plugin: 'session-hub',
    surface: 'terminal',
    component: 'Pane',
    requestId: 'session-hub',
    props: PANE_PROPS,
  })

  expect(await ui.find({ type: 'Text', text: /✗ Bash sleep 999/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /失敗\s*1/ })).toBeDefined()
})
