import { expect, test } from 'claude-code/testing'

const drain = async (stream: AsyncIterable<unknown>): Promise<void> => {
  for await (const _ of stream) void _
}

test('依頼を判定した段階で turn.step の effort を書き換える', async ($, on) => {
  on('turn.start', (_$, e) => ({ turnId: e.turnId }) as never)
  on('ui.status', () => ({ value: undefined }) as never)
  on('model.classify', () => ({ value: 'high' }) as never)
  let seen: unknown
  on('turn.step', async function* (_$, e) {
    seen = e.effort
    return { turnId: e.turnId, index: e.index, answer: '', toolUses: [], stopReason: 'end_turn', usage: null } as never
  })

  await $.turn.start({ text: '原因を調べて', turnId: 't1' } as never)
  await drain($.turn.step({ turnId: 't1', index: 0, model: 'claude-sonnet-5-5', effort: 'medium', messageCount: 1 } as never))
  expect(seen).toBe('high')
})

test('同意だけの短い入力は判定せず前の段階を引き継ぐ', async ($, on) => {
  on('turn.start', (_$, e) => ({ turnId: e.turnId }) as never)
  on('ui.status', () => ({ value: undefined }) as never)
  let calls = 0
  on('model.classify', () => {
    calls += 1
    return { value: 'xhigh' } as never
  })
  let seen: unknown
  on('turn.step', async function* (_$, e) {
    seen = e.effort
    return { turnId: e.turnId, index: e.index, answer: '', toolUses: [], stopReason: 'end_turn', usage: null } as never
  })

  await $.turn.start({ text: '全体を監査して', turnId: 't1' } as never)
  await drain($.turn.step({ turnId: 't1', index: 0, model: 'claude-opus-5-5', effort: 'medium', messageCount: 1 } as never))
  await $.turn.start({ text: 'OK', turnId: 't2' } as never)
  await drain($.turn.step({ turnId: 't2', index: 0, model: 'claude-opus-5-5', effort: 'medium', messageCount: 3 } as never))
  expect(calls).toBe(1)
  expect(seen).toBe('xhigh')
})

test('非対応モデルは書き換えない', async ($, on) => {
  on('turn.start', (_$, e) => ({ turnId: e.turnId }) as never)
  on('ui.status', () => ({ value: undefined }) as never)
  on('model.classify', () => ({ value: 'low' }) as never)
  let seen: unknown
  on('turn.step', async function* (_$, e) {
    seen = e.effort
    return { turnId: e.turnId, index: e.index, answer: '', toolUses: [], stopReason: 'end_turn', usage: null } as never
  })

  await $.turn.start({ text: 'こんにちは', turnId: 't1' } as never)
  await drain($.turn.step({ turnId: 't1', index: 0, model: 'claude-sonnet-4-5', effort: 'high', messageCount: 1 } as never))
  expect(seen).toBe('high')
})

test('サブエージェントは親ターンの段階を継承する（別 turnId でも）', async ($, on) => {
  on('turn.start', (_$, e) => ({ turnId: e.turnId }) as never)
  on('ui.status', () => ({ value: undefined }) as never)
  on('model.classify', () => ({ value: 'high' }) as never)
  const seen: unknown[] = []
  on('turn.step', async function* (_$, e) {
    seen.push(e.effort)
    return { turnId: e.turnId, index: e.index, answer: '', toolUses: [], stopReason: 'end_turn', usage: null } as never
  })

  await $.turn.start({ text: '原因を調べて', turnId: 't1' } as never)
  await drain($.turn.step({ turnId: 't1', index: 0, model: 'claude-sonnet-5-5', effort: 'medium', messageCount: 1 } as never))
  await drain($.turn.step({ turnId: 'sub1', agentId: 'a1', index: 0, model: 'claude-sonnet-5-5', effort: 'low', messageCount: 1 } as never))
  expect(seen).toEqual(['high', 'high'])
})

test('high plan 判定では EnterPlanMode を1回だけ呼び、effort は high にする', async ($, on) => {
  on('turn.start', (_$, e) => ({ turnId: e.turnId }) as never)
  on('ui.status', () => ({ value: undefined }) as never)
  on('model.classify', () => ({ value: 'high plan' }) as never)
  let plans = 0
  on('tool.call', { tool: 'EnterPlanMode' }, () => {
    plans += 1
    return { result: { text: 'ok' } } as never
  })
  let seen: unknown
  on('turn.step', async function* (_$, e) {
    seen = e.effort
    return { turnId: e.turnId, index: e.index, answer: '', toolUses: [], stopReason: 'end_turn', usage: null } as never
  })

  await $.turn.start({ text: '認証まわりを全面的に作り直したい', turnId: 't1' } as never)
  await drain($.turn.step({ turnId: 't1', index: 0, model: 'claude-sonnet-5-5', effort: 'medium', messageCount: 1 } as never))
  await drain($.turn.step({ turnId: 't1', index: 1, model: 'claude-sonnet-5-5', effort: 'medium', messageCount: 2 } as never))
  expect(plans).toBe(1)
  expect(seen).toBe('high')
})

test('plan 無しの判定・同意入力では EnterPlanMode を呼ばない', async ($, on) => {
  on('turn.start', (_$, e) => ({ turnId: e.turnId }) as never)
  on('ui.status', () => ({ value: undefined }) as never)
  on('model.classify', () => ({ value: 'high' }) as never)
  let plans = 0
  on('tool.call', { tool: 'EnterPlanMode' }, () => {
    plans += 1
    return { result: { text: 'ok' } } as never
  })

  await $.turn.start({ text: '原因を調べて', turnId: 't1' } as never)
  await $.turn.start({ text: 'OK', turnId: 't2' } as never)
  expect(plans).toBe(0)
})

test('plan off で自動切替だけ止める', async ($, on) => {
  on('turn.start', (_$, e) => ({ turnId: e.turnId }) as never)
  on('ui.status', () => ({ value: undefined }) as never)
  on('model.classify', () => ({ value: 'xhigh plan' }) as never)
  let plans = 0
  on('tool.call', { tool: 'EnterPlanMode' }, () => {
    plans += 1
    return { result: { text: 'ok' } } as never
  })

  await $.command.run({ command: 'effort-router', args: 'plan off' } as never)
  await $.turn.start({ text: '全体を監査して', turnId: 't1' } as never)
  expect(plans).toBe(0)
})
