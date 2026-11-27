local wezterm = require 'wezterm'
local act = wezterm.action

local config = {}

if wezterm.config_builder then
  config = wezterm.config_builder()
end

-- OS 判定（Windows / macOS 共通ファイル。OS 固有の設定は分岐の中に書く）
local is_windows = wezterm.target_triple:find('windows') ~= nil

-- 共通: nvim の画像表示（snacks.nvim）に必要
config.enable_kitty_graphics = true

-- 共通: 表示・動作
config.automatically_reload_config = true
config.font_size = 12.0
config.use_ime = true
config.window_background_opacity = 0.85
config.macos_window_background_blur = 20 -- macOS のみ有効
config.window_decorations = 'RESIZE'

-- 背景画像（Windows Terminal と同じ: 不透明度 0.25・中央・全面に拡大）。
-- 画像が config ディレクトリに無ければ設定しない（Windows は setup.bat がコピー）
local bg_image = wezterm.config_dir .. '/background.png'
local bg_file = io.open(bg_image, 'rb')
if bg_file then
  bg_file:close()
  config.background = {
    { source = { Color = '#0C0C0C' }, width = '100%', height = '100%' },
    {
      source = { File = bg_image },
      opacity = 0.25,
      horizontal_align = 'Center',
      vertical_align = 'Middle',
      width = 'Cover',
      height = 'Cover',
    },
  }
end

if is_windows then
  -- WSL Ubuntuをデフォルトドメインとして設定
  config.default_domain = 'WSL:Ubuntu'

  -- Windows Terminal と同じキー設定
  config.keys = {
    -- Shift+Enter: ESC + CR を送信（ClaudeCode で改行）
    { key = 'Enter', mods = 'SHIFT', action = act.SendString '\x1b\r' },

    -- Ctrl+C: 選択中ならコピー、未選択なら通常の Ctrl+C（中断）を送信
    {
      key = 'c',
      mods = 'CTRL',
      action = wezterm.action_callback(function(window, pane)
        local sel = window:get_selection_text_for_pane(pane)
        if sel and sel ~= '' then
          window:perform_action(act.CopyTo 'Clipboard', pane)
          window:perform_action(act.ClearSelection, pane)
        else
          window:perform_action(act.SendKey { key = 'c', mods = 'CTRL' }, pane)
        end
      end),
    },

    -- Ctrl+V: 常にクリップボードから貼り付け
    -- (powershell.exe による画像判定は同期起動で遅延が出るため廃止。画像は Ctrl+Shift+V)
    { key = 'v', mods = 'CTRL', action = act.PasteFrom 'Clipboard' },

    -- Ctrl+Shift+V: 生の Ctrl+V（0x16）をアプリへ送信（ClaudeCode の画像貼り付け用）
    { key = 'V', mods = 'CTRL|SHIFT', action = act.SendString '\x16' },

    -- Ctrl+Shift+Z: Ctrl+Y（0x19）を送信（Redo）
    { key = 'Z', mods = 'CTRL|SHIFT', action = act.SendString '\x19' },

    -- Ctrl+Shift+F: 検索
    { key = 'F', mods = 'CTRL|SHIFT', action = act.Search { CaseSensitiveString = '' } },

    -- Alt+Shift+D: ペイン分割（幅が広ければ左右、狭ければ上下）
    {
      key = 'D',
      mods = 'ALT|SHIFT',
      action = wezterm.action_callback(function(window, pane)
        local dim = pane:get_dimensions()
        local direction = (dim.pixel_width > dim.pixel_height) and 'Right' or 'Down'
        window:perform_action(
          act.SplitPane { direction = direction, domain = 'CurrentPaneDomain' },
          pane
        )
      end),
    },
  }
else
  -- macOS: Cmd 系の既定キーをそのまま使う。Shift+Enter のみ ClaudeCode の改行用に追加
  config.keys = {
    { key = 'Enter', mods = 'SHIFT', action = act.SendString '\x1b\r' },
  }
end

return config
