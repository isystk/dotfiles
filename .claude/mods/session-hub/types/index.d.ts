export type CallStatus = 'running' | 'ok' | 'error' | 'denied'

export type Call = {
  id: string
  tool: string
  label: string
  status: CallStatus
  isSub: boolean
  startedAt: number
  durationMs: number | null
}

export type Edited = { file: string; tool: string; count: number }

export type Hub = {
  turnNo: number
  isWorking: boolean
  turnStartedAt: number
  lastMs: number | null
  calls: Call[]
  edited: Edited[]
  failures: number
  inputTokens: number
  outputTokens: number
  cacheReadTokens: number
  cacheWriteTokens: number
}

declare module 'claude-code' {
  interface PluginState {
    'session-hub': { hub: Hub; isPaneOpen: boolean }
  }
}
