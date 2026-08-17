--[[
Neovim設定

前提:
- lazy.nvim: 初回起動時に自動インストール
- 外部コマンド: git / prettier / pint(PHP) / eslint (フォーマット・Lintに使用)
- Nerd Font (nvim-web-devicons のアイコン表示に必要)
- macOS: macism (brew tap laishulu/homebrew && brew install macism) → IME自動切替に使用

主要キーマップ (<leader> = Space):
- <C-n> / <leader>e        ファイルツリー切替 (neo-tree)
- <C-p> / <Space><Space>   ファイル検索 (telescope)
- <leader>fg               全文検索
- <leader>fb               バッファ一覧
- <leader>tc               ターミナル切替
- <leader>ts (visual)      選択範囲をターミナルへ送信
- <leader>ac               ClaudeCode切替
- <S-Tab>                  ウィンドウ移動
- gd / K / gr / <leader>rn / <leader>ca   LSP: 定義 / hover / 参照 / rename / code action

構成:
1. 基本設定  2. プラグイン(lazy.nvim)  3. 外観・挙動  4. キーマッピング
5. 自動保存  6. OSC52クリップボード(SSH接続時)  7. macOS専用設定

起動モード:
- nvim <ファイルパス>
    通常起動。左にファイルツリー(neo-tree)、右にファイルを表示。
- nvim --cmd 'let g:panels=1' <ファイルパス>
    IDEレイアウトで起動。ターミナル・ClaudeCodeを含む複数パネルを展開する。
--]]

-- ==========================================================
-- 1. 基本設定 (Encoding, etc.)
-- ==========================================================
-- 読込時の文字コード自動判定候補（encoding自体は常にutf-8固定のため設定不要）
vim.opt.fileencodings = 'ucs-boms,utf-8,euc-jp,cp932'
vim.opt.fileformats   = 'unix,dos,mac'
vim.opt.termguicolors = true

vim.g.mapleader = ' '

-- neo-tree.nvimのreveal(非同期navigate完了時)は無条件でnvim_set_current_win()を
-- 呼び、対象ウィンドウが閉じられていると"Invalid window id"で落ちる(プラグイン側の
-- 潜在バグ)。プラグイン本体は無改造のまま、validチェック付きに差し替えて防御する。
do
  local orig_set_current_win = vim.api.nvim_set_current_win
  vim.api.nvim_set_current_win = function(win)
    if vim.api.nvim_win_is_valid(win) then
      orig_set_current_win(win)
    end
  end
end

-- 下部ターミナルの表示/非表示トグル(既存バッファを再利用)
local wsl_toggle_buf = nil
local function toggle_wsl_terminal()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.w[win].is_wsl_terminal then
      wsl_toggle_buf = vim.api.nvim_win_get_buf(win)
      vim.api.nvim_win_close(win, false)
      return
    end
  end
  local file_win = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.w[win].is_file_win then
      file_win = win
      break
    end
  end
  if file_win and vim.api.nvim_win_is_valid(file_win) then
    vim.api.nvim_set_current_win(file_win)
  end

  if wsl_toggle_buf and vim.api.nvim_buf_is_valid(wsl_toggle_buf) then
    vim.cmd('belowright sbuffer ' .. wsl_toggle_buf)
  else
    vim.cmd('belowright split | terminal')
  end
  vim.w[0].is_wsl_terminal = true
  vim.api.nvim_win_set_height(0, 15) -- 既定分割比率(50%)を15行固定へ矯正
end
vim.keymap.set('n', '<leader>tc', toggle_wsl_terminal, { desc = 'WSLターミナル切替' })

-- ターミナルへテキスト送信(既存バッファ無ければ開く)。windowを操作するため、
-- 呼び出し元はvisualモードを抜けてノーマルモードで実行すること
local function send_text_to_terminal(text)
  local term_win = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.w[win].is_wsl_terminal then
      term_win = win
      break
    end
  end
  if not term_win then
    toggle_wsl_terminal()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.w[win].is_wsl_terminal then
        term_win = win
      end
    end
  end
  if not term_win then
    return
  end
  local term_buf = vim.api.nvim_win_get_buf(term_win)
  local job_id = vim.b[term_buf].terminal_job_id
  if job_id then
    vim.fn.chansend(job_id, text)
  end
  vim.api.nvim_set_current_win(term_win) -- 送信先パネルへカーソル移動
end

-- 選択範囲をZshターミナルパネルへ送信。"zyでvisualモードを抜けてから
-- window操作する(visualモード中にsplit/closeするとレイアウトが壊れるため)
local function send_selection_to_terminal()
  vim.cmd('normal! "zy')
  local text = vim.fn.getreg('z')
  send_text_to_terminal(text)
end
vim.keymap.set('v', '<leader>ts', send_selection_to_terminal, { desc = '選択範囲をターミナルへ送信' })

-- ターミナルアプリのリサイズでSnacks/vim標準の比例縮小が起き、
-- ClaudeCode(右)幅・WSLターミナル(下)高さが崩れるため、リサイズの都度矯正する
vim.api.nvim_create_autocmd('VimResized', {
  callback = function()
    vim.schedule(function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.w[win].is_wsl_terminal then
          pcall(vim.api.nvim_win_set_height, win, 15)
        end
        local snacks_win = vim.w[win].snacks_win
        if snacks_win and snacks_win.position == 'right' then
          -- neo-tree(固定40列)・メインエディタ(最低40列)を圧迫しないよう
          -- 画面全体columnsに収まる範囲でClaudeCode幅をクランプする
          local neotree_width = 0
          for _, w in ipairs(vim.api.nvim_list_wins()) do
            if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'neo-tree' then
              neotree_width = 40
              break
            end
          end
          local min_editor_width = 40
          local max_allowed = vim.o.columns - neotree_width - min_editor_width
          local width = math.max(20, math.min(65, max_allowed))
          pcall(vim.api.nvim_win_set_width, win, width)
        end
      end
    end)
  end,
})

-- ターミナルバッファ内で最下部(プロンプト入力行)にいる時だけインサートモードにする。
-- 出力結果(スクロールバック領域)をクリック・カーソル移動した場合はノーマルモードのまま維持する
local function is_terminal_cursor_at_bottom()
  return vim.api.nvim_win_get_cursor(0)[1] == vim.api.nvim_buf_line_count(0)
end

vim.api.nvim_create_autocmd('WinEnter', {
  callback = function()
    if vim.bo.buftype == 'terminal' and is_terminal_cursor_at_bottom() then
      vim.cmd('startinsert')
    end
  end,
})
vim.api.nvim_create_autocmd('WinLeave', {
  callback = function()
    if vim.bo.buftype == 'terminal' then
      vim.cmd('stopinsert')
    end
  end,
})

-- ターミナルバッファ内でクリック等によりカーソル移動しノーマルモードへ落ちた場合、
-- 最下部(プロンプト入力行)ならインサートモードへ戻し、出力結果部分ならノーマルモードのまま維持する
-- (CursorMovedはノーマルモード中のカーソル移動でのみ発火するため、クリック直後のノーマル化を確実に検知できる。
-- <LeftMouse>への直接マッピングはクリック1回目がNeovim内部処理として消費され発火しなかった)
vim.api.nvim_create_autocmd('CursorMoved', {
  callback = function()
    if vim.bo.buftype == 'terminal' then
      if is_terminal_cursor_at_bottom() then
        vim.cmd('startinsert')
      else
        vim.cmd('stopinsert')
      end
    end
  end,
})

-- 現在セッション内で開いたファイルのMRU(直近アクセス順)を独自管理する。
-- vim.v.oldfilesはshadaファイル由来の静的スナップショットのため、
-- セッション中の実際の閲覧順(直前に触ったファイルが先頭)とは必ずしも一致しない対策。
local session_mru = {} -- 絶対パスの配列。先頭が最新
vim.api.nvim_create_autocmd('BufEnter', {
  callback = function()
    local bufname = vim.api.nvim_buf_get_name(0)
    if bufname == '' or vim.bo.buftype ~= '' or vim.fn.filereadable(bufname) == 0 then
      return
    end
    local abs_path = vim.fn.fnamemodify(bufname, ':p')
    for i, p in ipairs(session_mru) do
      if p == abs_path then
        table.remove(session_mru, i)
        break
      end
    end
    table.insert(session_mru, 1, abs_path)
  end,
})

-- Windowsパス(.config\nvim\init.lua等)の"\"がfuzzy matchを阻害するため、
-- matcherへ渡す直前のqueryで"/"へ変換する。
-- 初期表示は最近開いたファイル(session_mru優先 + oldfilesで補完)、入力すると全ファイル検索へ動的切替する。
local function telescope_find_files_win_path()
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values

  local find_command = {
    'rg', '--files', '--hidden', '--no-ignore', -- .envなどドットファイル・.gitignore対象も検索対象に含める
    '--glob', '!.git/*', '--glob', '!.history/*', '--glob', '!node_modules/*', '--glob', '!vendor/*',
  }

  local function recent_files()
    local results = {}
    local seen = {}

    -- 今セッションで実際に開いた順(直近優先)。session_mru自体が既にMRU順のため未ソート
    for _, abs_path in ipairs(session_mru) do
      if vim.fn.filereadable(abs_path) == 1 then
        local rel = vim.fn.fnamemodify(abs_path, ':.')
        if not seen[rel] then
          seen[rel] = true
          table.insert(results, rel)
        end
      end
    end

    -- 今セッションで未アクセスの過去履歴をshadaのoldfilesから補完(重複はパス表記ゆれ込みでdedup)
    for _, f in ipairs(vim.v.oldfiles) do
      if vim.fn.filereadable(f) == 1 then
        local rel = vim.fn.fnamemodify(f, ':.')
        if not seen[rel] then
          seen[rel] = true
          table.insert(results, rel)
        end
      end
    end

    return results
  end

  -- 全ファイル一覧は初回入力時のみrg実行しキャッシュ(入力毎の再実行を避ける)
  local all_files_cache = nil

  pickers.new({}, {
    prompt_title = 'ファイル検索',
    sorting_strategy = 'ascending', -- 直近ファイルを画面最上部に表示(デフォルトのdescendingだと最下部に来るため)
    finder = finders.new_dynamic({
      entry_maker = function(entry)
        return { value = entry, display = entry, ordinal = entry }
      end,
      fn = function(prompt)
        if not prompt or prompt == '' then
          return recent_files()
        end
        all_files_cache = all_files_cache or vim.fn.systemlist(find_command)
        return all_files_cache
      end,
    }),
    sorter = conf.file_sorter({}),
    previewer = conf.file_previewer({}),
    on_input_filter_cb = function(query)
      return { prompt = query:gsub('\\', '/') }
    end,
  }):find()
end

-- ==========================================================
-- 2. lazy.nvim (Plugin Management)
-- ==========================================================
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    'git', 'clone', '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    '--branch=stable',
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require('lazy').setup({

  -- --- 外観・UI ---
  { 'tomasr/molokai' },
  { 'itchyny/lightline.vim' },
  {
    'lukas-reineke/indent-blankline.nvim',
    main = 'ibl',
    opts = {},
  },
  { 'bronson/vim-trailing-whitespace' },

  -- --- 開発サポート ---
  {
    'nvim-treesitter/nvim-treesitter',
    lazy  = false, -- lazy-loading非対応プラグインのため即時ロード必須
    build = ':TSUpdate',
    config = function()
      -- blade は公式パーサー一覧に無いため TSUpdate 時にカスタム登録する
      vim.api.nvim_create_autocmd('User', {
        pattern = 'TSUpdate',
        callback = function()
          require('nvim-treesitter.parsers').blade = {
            install_info = {
              url     = 'https://github.com/EmranMR/tree-sitter-blade',
              queries = 'queries',
            },
          }
        end,
      })
      vim.filetype.add({ pattern = { ['.*%.blade%.php'] = 'blade' } })

      local ts_filetypes = { 'javascript', 'typescript', 'tsx', 'php', 'html', 'css', 'json', 'lua', 'vim', 'blade' }
      require('nvim-treesitter').install(ts_filetypes)
      vim.api.nvim_create_autocmd('FileType', {
        pattern = ts_filetypes,
        callback = function()
          -- パーサー未取得(インストール未完了)時にエラーで落ちないようにする
          pcall(vim.treesitter.start)
        end,
      })
    end,
  },
  {
    'windwp/nvim-ts-autotag',
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    opts = {},
  },
  {
    'alvan/vim-closetag',
    init = function()
      vim.g.closetag_filenames = '*.html,*.xhtml,*.phtml,*.erb,*.php'
    end,
  },
  {
    'adalessa/laravel.nvim',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-telescope/telescope.nvim',
      'MunifTanjim/nui.nvim',
      'nvim-neotest/nvim-nio',
    },
    keys = {
      { '<leader>la', function() Laravel.pickers.artisan() end, desc = 'Laravel: Artisan Picker' },
      { '<leader>lr', function() Laravel.pickers.routes() end, desc = 'Laravel: Routes Picker' },
      { '<leader>lo', function() Laravel.pickers.related() end, desc = 'Laravel: Related Picker' },
      {
        'gf',
        function()
          if Laravel.app('gf').cursorOnResource() then
            return "<cmd>lua Laravel.commands.run('gf')<cr>"
          end
          return 'gf'
        end,
        expr = true, noremap = true, desc = 'Laravel: Go to resource(view/route/config等へジャンプ)',
      },
    },
    ft = { 'php', 'blade' },
    event = { 'BufEnter composer.json' },
    opts = {},
  },

  {
    'akinsho/git-conflict.nvim',
    version = '*',
    opts = {}, -- コンフリクトマーカーのハイライトとco/ct/cb/c0(ours/theirs/both/none選択)・]x/[x(次/前へ移動)を有効化
  },

  -- --- LSP (旧 tsuquyomi / syntastic 後継) ---
  {
    'mason-org/mason.nvim',
    opts = {},
  },
  {
    'mason-org/mason-lspconfig.nvim',
    dependencies = { 'mason-org/mason.nvim', 'neovim/nvim-lspconfig', 'saghen/blink.cmp' },
    opts = {
      ensure_installed = { 'ts_ls', 'intelephense', 'html', 'cssls', 'jsonls' },
      handlers = {
        function(server_name)
          require('lspconfig')[server_name].setup({
            capabilities = require('blink.cmp').get_lsp_capabilities(),
          })
        end,
      },
    },
  },
  {
    'neovim/nvim-lspconfig',
    config = function()
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('LspKeymaps', { clear = true }),
        callback = function(args)
          local opts = { buffer = args.buf, silent = true }
          vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
          vim.keymap.set('n', '<C-LeftMouse>', function()
            local mouse = vim.fn.getmousepos()
            vim.api.nvim_win_set_cursor(mouse.winid, { mouse.line, mouse.column - 1 })
            vim.lsp.buf.definition()
          end, opts)
          vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
          vim.keymap.set('n', 'gr', vim.lsp.buf.references, opts)
          vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, opts)
          vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, opts)
          vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, opts)
          vim.keymap.set('n', ']d', vim.diagnostic.goto_next, opts)
        end,
      })
    end,
  },
  {
    'coder/claudecode.nvim',
    dependencies = { 'folke/snacks.nvim' },
    opts = {
      terminal_cmd = 'claude --agent evolver',
      terminal = {
        split_width_percentage = 65, -- 1以上は絶対列数として扱われる(snacks.win仕様)。ターミナル全体幅に追従させず固定
        diff_split_width_percentage = 65, -- diff表示時も同じ固定幅を維持
        snacks_win_opts = {
          wo = { winfixwidth = true }, -- Snacksのsplitはon_resize時に幅再計算しないため、
          -- 他ウィンドウの縮小/拡大時にVimネイティブの比例リサイズ対象から外し幅を固定する
        },
      },
      diff_opts = {
        layout = 'unified', -- 新規分割せず現在バッファ内に差分表示
        auto_resize_terminal = true, -- diff展開時のwincmd均等化後、0.30へ戻すため必須
        keep_terminal_focus = true, -- diff展開後もClaudeCodeパネルへフォーカス・インサートモードを維持する
      },
    },
    init = function()
      -- 以下、diff表示(ClaudeCodeDiffOpened/Closed)時のwincmd均等化によって
      -- neo-tree幅・WSLターミナル・ファイルパネルのレイアウトが崩れるのを防ぐ処理。
      -- プラグイン本体は無改造。
      local wsl_term_buf = nil

      local function find_win_by_marker(marker)
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.w[win][marker] then
            return win
          end
        end
        return nil
      end

      -- ClaudeCodeパネルへフォーカス+インサートモードを戻す(複数回リトライで保険)
      local function ensure_claudecode_terminal_insert()
        local function try_focus()
          local ok, term = pcall(require, 'claudecode.terminal')
          if not ok then
            return
          end
          local term_buf = term.get_active_terminal_bufnr()
          if not term_buf then
            return
          end
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_buf(win) == term_buf then
              vim.api.nvim_set_current_win(win)
              if vim.fn.mode() ~= 't' and vim.fn.mode() ~= 'i' then
                vim.cmd('startinsert')
              end
              break
            end
          end
        end
        for _, delay in ipairs({ 0, 50, 150, 300 }) do
          vim.defer_fn(try_focus, delay)
        end
      end

      -- diff表示中はneo-tree revealのInvalid window idクラッシュを防ぐため一時停止する
      -- (再開はファイル再表示処理の最後)
      vim.api.nvim_create_autocmd('User', {
        pattern = 'ClaudeCodeDiffOpened',
        callback = function()
          vim.g.__claudecode_skip_neotree_reveal = true
        end,
      })

      -- diff表示時は元ファイルパネルを閉じdiffパネルのみ表示(全幅化)。
      -- 終了後、閉じたファイルをis_file_winマーカーの位置へ再度開く。
      local hidden_diff_file_path = nil
      -- ウィンドウを閉じるとwinfixwidth指定済みのneo-treeへ空きスペースが
      -- 誤って譲渡され幅が広がることがあるため、閉じる前の幅を記憶し後で戻す
      local neotree_width_before_diff = nil

      vim.api.nvim_create_autocmd('User', {
        pattern = 'ClaudeCodeDiffOpened',
        callback = function(args)
          local data = args.data or {}
          local target_win = data.target_window
          local diff_win = data.diff_window
          if not target_win or not diff_win or target_win == diff_win then
            return
          end
          if not vim.api.nvim_win_is_valid(target_win) or not vim.api.nvim_win_is_valid(diff_win) then
            return
          end
          hidden_diff_file_path = data.file_path
          local neotree_win = nil
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_buf_get_option(vim.api.nvim_win_get_buf(win), 'filetype') == 'neo-tree' then
              neotree_win = win
              break
            end
          end
          if neotree_win then
            neotree_width_before_diff = vim.api.nvim_win_get_width(neotree_win)
          end
          vim.api.nvim_win_close(target_win, false)
        end,
      })
      vim.api.nvim_create_autocmd('User', {
        pattern = 'ClaudeCodeDiffClosed',
        callback = function()
          local file_path = hidden_diff_file_path
          hidden_diff_file_path = nil
          if not file_path or file_path == '' then
            return
          end
          vim.schedule(function()
            -- 再表示中もneo-tree revealのInvalid window idクラッシュを防ぐため停止する
            vim.g.__claudecode_skip_neotree_reveal = true

            local file_win = find_win_by_marker('is_file_win')
            if not file_win or not vim.api.nvim_win_is_valid(file_win) then
              -- マーカー付きウィンドウが残ってない場合、terminal/neo-tree以外の
              -- 適当なウィンドウを探して代用する
              for _, win in ipairs(vim.api.nvim_list_wins()) do
                local buf = vim.api.nvim_win_get_buf(win)
                local buftype = vim.api.nvim_buf_get_option(buf, 'buftype')
                local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
                if buftype ~= 'terminal' and ft ~= 'neo-tree' then
                  file_win = win
                  break
                end
              end
            end

            if file_win and vim.api.nvim_win_is_valid(file_win) then
              vim.api.nvim_set_current_win(file_win)
            else
              -- 表示先が1つも残ってない場合は新規作成。カレントがneo-treeだと
              -- 分割時に幅・表示モードが崩れるため、先にneo-tree以外へ退避する
              if vim.bo.filetype == 'neo-tree' then
                for _, win in ipairs(vim.api.nvim_list_wins()) do
                  if vim.api.nvim_buf_get_option(vim.api.nvim_win_get_buf(win), 'filetype') ~= 'neo-tree' then
                    vim.api.nvim_set_current_win(win)
                    break
                  end
                end
              end
              vim.cmd('vsplit')
            end
            vim.cmd('edit ' .. vim.fn.fnameescape(file_path))
            vim.w[0].is_file_win = true

            vim.schedule(function()
              vim.g.__claudecode_skip_neotree_reveal = false
            end)
          end)
        end,
      })

      -- ターミナルはdiff表示中一時非表示にし、diff終了後30%高さで復元する
      -- (ファイル再表示処理の後に登録し、is_file_win復元済みの状態で高さ計算する)
      vim.api.nvim_create_autocmd('User', {
        pattern = 'ClaudeCodeDiffOpened',
        callback = function()
          local win = find_win_by_marker('is_wsl_terminal')
          if not win or not vim.api.nvim_win_is_valid(win) then
            return
          end
          wsl_term_buf = vim.api.nvim_win_get_buf(win)
          vim.api.nvim_win_close(win, false)
        end,
      })
      vim.api.nvim_create_autocmd('User', {
        pattern = 'ClaudeCodeDiffClosed',
        callback = function()
          vim.schedule(function()
            if not wsl_term_buf or not vim.api.nvim_buf_is_valid(wsl_term_buf) then
              return
            end
            for _, win in ipairs(vim.api.nvim_list_wins()) do
              if vim.api.nvim_win_get_buf(win) == wsl_term_buf then
                wsl_term_buf = nil
                return -- 既に表示済み
              end
            end
            local file_win = find_win_by_marker('is_file_win')
            if file_win and vim.api.nvim_win_is_valid(file_win) then
              vim.api.nvim_set_current_win(file_win)
            end
            vim.cmd('belowright sbuffer ' .. wsl_term_buf)
            vim.w[0].is_wsl_terminal = true
            vim.api.nvim_win_set_height(0, 15)
            wsl_term_buf = nil
            ensure_claudecode_terminal_insert() -- sbufferでフォーカスが奪われるため即座に戻す
          end)
        end,
      })

      -- 再表示処理完了後、diff表示前のneo-tree幅へ戻す
      -- (他のDiffClosedハンドラより後に登録し、schedule済みキューの最後で実行する)
      vim.api.nvim_create_autocmd('User', {
        pattern = 'ClaudeCodeDiffClosed',
        callback = function()
          local width = neotree_width_before_diff
          neotree_width_before_diff = nil
          if not width then
            return
          end
          vim.schedule(function()
            for _, win in ipairs(vim.api.nvim_list_wins()) do
              if vim.api.nvim_buf_get_option(vim.api.nvim_win_get_buf(win), 'filetype') == 'neo-tree' then
                pcall(vim.api.nvim_win_set_width, win, width)
                break
              end
            end
          end)
        end,
      })

      -- reveal停止フラグの保険復帰。早期returnでフラグが立ちっぱなしにならないよう
      -- diff終了ごとに必ず最後にfalseへ戻す
      vim.api.nvim_create_autocmd('User', {
        pattern = 'ClaudeCodeDiffClosed',
        callback = function()
          vim.schedule(function()
            vim.g.__claudecode_skip_neotree_reveal = false
          end)
        end,
      })

      -- diff表示後、プラグイン純正のkeep_terminal_focusだけだと他のレイアウト調整
      -- (resize/wincmd=等)や非同期のジョブ出力とタイミングが競合しノーマルモードへ
      -- 戻ることがあるため、時間差を空けて複数回リトライしインサートモードへ戻す保険をかける
      vim.api.nvim_create_autocmd('User', {
        pattern = 'ClaudeCodeDiffOpened',
        callback = ensure_claudecode_terminal_insert,
      })

      -- WSLターミナル再表示(belowright sbuffer)でフォーカスが奪われるため、
      -- diff終了時の再表示処理がすべて終わった後にClaudeCodeパネルへ戻す
      vim.api.nvim_create_autocmd('User', {
        pattern = 'ClaudeCodeDiffClosed',
        callback = ensure_claudecode_terminal_insert,
      })
    end,
    cmd = { 'ClaudeCode', 'ClaudeCodeFocus', 'ClaudeCodeSend', 'ClaudeCodeDiffAccept', 'ClaudeCodeDiffDeny' },
    keys = {
      { '<leader>ac', '<cmd>ClaudeCode<cr>', desc = 'Toggle Claude' },
      { '<leader>af', '<cmd>ClaudeCodeFocus<cr>', desc = 'Focus Claude' },
      { '<leader>as', '<cmd>ClaudeCodeSend<cr>', mode = 'v', desc = 'Send to Claude' },
      {
        '<leader>as',
        function()
          vim.cmd('ClaudeCodeTreeAdd')
          vim.cmd('ClaudeCodeFocus') -- 送信先パネル(ClaudeCode)へカーソル移動
        end,
        ft = { 'neo-tree' }, desc = 'Add file to Claude context',
      },
      { '<leader>aa', '<cmd>ClaudeCodeDiffAccept<cr>', desc = 'Accept diff' },
      { '<leader>ad', '<cmd>ClaudeCodeDiffDeny<cr>', desc = 'Deny diff' },
    },
  },

  -- --- フォーマット・Lint ---
  {
    'stevearc/conform.nvim',
    event = { 'BufWritePre' },
    cmd = { 'ConformInfo' },
    opts = {
      formatters_by_ft = {
        javascript = { 'prettier' },
        typescript = { 'prettier' },
        javascriptreact = { 'prettier' },
        typescriptreact = { 'prettier' },
        css = { 'prettier' },
        html = { 'prettier' },
        json = { 'prettier' },
        php = { 'pint' },
      },
      format_on_save = { timeout_ms = 2000, lsp_fallback = true },
    },
  },
  {
    'mfussenegger/nvim-lint',
    event = { 'BufWritePost', 'BufReadPost', 'InsertLeave' },
    config = function()
      require('lint').linters_by_ft = {
        javascript = { 'eslint' },
        typescript = { 'eslint' },
        javascriptreact = { 'eslint' },
        typescriptreact = { 'eslint' },
      }
      vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufReadPost', 'InsertLeave' }, {
        callback = function()
          require('lint').try_lint()
        end,
      })
    end,
  },

  -- --- ファイラー・検索 ---
  {
    'nvim-neo-tree/neo-tree.nvim',
    branch = 'v3.x',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-tree/nvim-web-devicons',
      'MunifTanjim/nui.nvim',
    },
    lazy = false, -- VimEnter autocmd(ツリー/ClaudeCode自動表示)を起動時に確実に登録するため即時ロード
    cmd = 'Neotree',
    keys = {
      { '<C-n>', '<cmd>Neotree toggle<cr>', desc = 'ファイルツリー切替' },
      { '<leader>e', '<cmd>Neotree toggle<cr>', desc = 'ファイルツリー切替' },
    },
    opts = {
      close_if_last_window = true,
      filesystem = {
        filtered_items = {
          visible = true, -- 隠しファイルも表示 (旧NERDTreeShowHidden相当)
        },
      },
    },
    config = function(_, opts)
      require('neo-tree').setup(opts)

      local augroup = vim.api.nvim_create_augroup('NeoTreeSetting', { clear = true })
      vim.api.nvim_create_autocmd('FileType', {
        group = augroup,
        pattern = 'neo-tree',
        callback = function(args)
          -- 他ウィンドウ開閉時のwincmd均等化でNeo-tree幅が崩れないよう固定する
          vim.wo.winfixwidth = true

          -- カーソル位置ファイルのパスをターミナルへ入力(実行はしない)
          vim.keymap.set('n', '<leader>ts', function()
            local state = require('neo-tree.sources.manager').get_state('filesystem')
            local node = state and state.tree and state.tree:get_node()
            if not node then
              return
            end
            local path = node.path or node:get_id()
            path = vim.fn.fnamemodify(path, ':.')
            send_text_to_terminal(path)
          end, { buffer = args.buf, desc = 'カーソル位置ファイルパスをターミナルへ入力' })
        end,
      })
      vim.api.nvim_create_autocmd('VimEnter', {
        group = augroup,
        callback = function()
          -- 起動時 --cmd "let g:panels=1" 指定時のみ複数パネル(ClaudeCode+ターミナル+Neotree)を展開する
          if vim.g.panels ~= 1 then
            vim.cmd('Neotree show')
            vim.cmd('stopinsert')
            return
          end

          local file_name = vim.fn.expand('%')
          local has_file = file_name ~= '' and vim.fn.isdirectory(file_name) == 0

          if not has_file then
            -- ファイル未指定時: カレントディレクトリの先頭ファイル(隠しファイル除く・名前順)を自動で開く
            local entries = vim.fn.readdir(vim.fn.getcwd())
            table.sort(entries)
            for _, name in ipairs(entries) do
              if vim.fn.isdirectory(name) == 0 and not name:match('^%.') then
                vim.cmd('edit ' .. vim.fn.fnameescape(name))
                has_file = true
                break
              end
            end
          end

          if has_file then
            -- 右端にClaudeCode、中央はファイル(上)・ターミナル(下)の3カラム構成にする
            local file_win = vim.api.nvim_get_current_win()
            vim.w[file_win].is_file_win = true -- diff表示時のターミナル再表示先を特定するためのマーカー
            vim.cmd('ClaudeCode')
            vim.api.nvim_set_current_win(file_win)
            vim.cmd('belowright split')
            vim.cmd('terminal')
            vim.w[0].is_wsl_terminal = true -- diff表示時の一時非表示/再表示で識別するためのマーカー
            vim.api.nvim_win_set_height(0, 15)
            vim.api.nvim_set_current_win(file_win)
          else
            local file_win = vim.api.nvim_get_current_win()
            vim.cmd('ClaudeCode')
            vim.api.nvim_win_close(file_win, false)
          end

          -- レイアウト確定後にNeotreeを開く(先に開くとwindow close処理と競合しInvalid window idになる)
          vim.cmd('Neotree show')

          -- ClaudeCode起動時に自動でインサートモードへ入る(auto_insertデフォルト)ため、
          -- 起動直後はノーマルモードへ戻す
          vim.cmd('stopinsert')
        end,
      })

      -- ファイルを開くたびNeo-treeを追従させる(reveal)
      vim.api.nvim_create_autocmd('BufEnter', {
        group = augroup,
        callback = function()
          if vim.g.__claudecode_skip_neotree_reveal then
            return -- diffパネルの閉じ直後の再表示中は、window id競合(Invalid window id)を避けるため一時停止
          end
          local bufname = vim.fn.expand('%')
          local buftype = vim.bo.buftype
          if bufname == '' or buftype ~= '' or vim.bo.filetype == 'neo-tree' then
            return
          end
          if vim.fn.isdirectory(bufname) == 1 then
            return
          end
          require('neo-tree.command').execute({ action = 'show', reveal = true, reveal_force_cwd = true })
        end,
      })
    end,
  },
  {
    'nvim-telescope/telescope.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function()
      require('telescope').setup({
        defaults = {
          mappings = {
            i = { ['<Esc>'] = require('telescope.actions').close },
          },
        },
      })
    end,
    keys = {
      { '<C-p>', telescope_find_files_win_path, desc = 'ファイル検索' },
      { '<Space><Space>', telescope_find_files_win_path, desc = 'ファイル検索' },
      { '<leader>fg', '<cmd>Telescope live_grep<cr>', desc = '全文検索' },
      { '<leader>fb', '<cmd>Telescope buffers<cr>', desc = 'バッファ一覧' },
      { '<leader>fr', '<cmd>Telescope oldfiles<cr>', desc = '最近使ったファイル' },
    },
  },
  {
    'folke/trouble.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    cmd = 'Trouble',
    opts = {},
    keys = {
      { '<leader>xx', '<cmd>Trouble diagnostics toggle<cr>', desc = '診断一覧' },
      { '<leader>xr', '<cmd>Trouble lsp_references toggle<cr>', desc = '参照一覧' },
    },
  },

  -- --- 入力補完 ---
  {
    'zbirenbaum/copilot.lua',
    cmd = 'Copilot',
    event = 'InsertEnter',
    opts = {
      suggestion = { enabled = false }, -- ghost text表示はblink.cmp側の補完候補に統合するため無効化
      panel      = { enabled = false },
    },
  },
  {
    'saghen/blink.cmp',
    version = '1.*',
    dependencies = { 'fang2hou/blink-copilot' },
    opts = {
      keymap = { preset = 'default' },
      completion = { documentation = { auto_show = true } },
      sources = {
        default = { 'lsp', 'path', 'snippets', 'buffer', 'copilot' },
        providers = {
          copilot = {
            name = 'copilot',
            module = 'blink-copilot',
            score_offset = 100,
            async = true,
          },
        },
      },
    },
  },

}, {
  -- lazy.nvim オプション
  install = { colorscheme = { 'molokai', 'default' } },
})

-- ==========================================================
-- 3. 外観・挙動設定
-- ==========================================================
vim.opt.number      = true
vim.opt.cursorline  = true
vim.opt.virtualedit = 'block'
vim.opt.laststatus  = 2
vim.opt.equalalways = false

-- 外部(Claude Code等)によるファイル変更を自動検知して再読込する
vim.opt.autoread = true
vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter', 'CursorHold', 'CursorHoldI' }, {
  command = 'checktime',
})

-- インデント
vim.opt.expandtab   = true
vim.opt.tabstop     = 2
vim.opt.softtabstop = 2
vim.opt.shiftwidth  = 2
vim.opt.autoindent  = true
vim.opt.smartindent = true

-- 検索
vim.opt.incsearch  = true
vim.opt.ignorecase = true
vim.opt.smartcase  = true
vim.opt.hlsearch   = true

-- コマンド・マウス
vim.opt.wildmenu = true
vim.opt.history  = 5000
vim.opt.mouse    = 'a'

-- Molokai カスタム配色
local mycolors_group = vim.api.nvim_create_augroup('MyColors', { clear = true })
vim.api.nvim_create_autocmd('ColorScheme', {
  group   = mycolors_group,
  pattern = 'molokai',
  callback = function()
    vim.cmd('highlight Normal      ctermbg=none')
    vim.cmd('highlight Comment     ctermfg=22 guifg=#008800')
    vim.cmd('highlight Visual      ctermfg=8  guifg=#EEEEEE')
    vim.cmd('highlight MatchParen  cterm=underline gui=underline guibg=NONE')
  end,
})

vim.g.molokai_original    = 1
vim.g.re_visual_selection = 0
vim.cmd('colorscheme molokai')

-- ==========================================================
-- 4. キーマッピング
-- ==========================================================
local noremap_silent = { noremap = true, silent = true }

-- 検索ハイライト切り替え
vim.keymap.set('n', '<Esc><Esc>', ':<C-u>set nohlsearch!<CR>', noremap_silent)

-- Tab / インデント
vim.keymap.set('n', '<Tab>', '%',    noremap_silent)
vim.keymap.set('v', '<Tab>', '>gv',  noremap_silent)
vim.keymap.set('v', '<S-Tab>', '<gv', noremap_silent)

-- ヤンク・ペースト
vim.keymap.set('v', 'p',    '"0p', noremap_silent)
vim.keymap.set('v', '<S-p>', '"0p', noremap_silent)

-- インサートモード移動
vim.keymap.set('i', '<C-k>', '<Up>',    noremap_silent)
vim.keymap.set('i', '<C-j>', '<Down>',  noremap_silent)
vim.keymap.set('i', '<C-h>', '<Left>',  noremap_silent)
vim.keymap.set('i', '<C-l>', '<Right>', noremap_silent)

-- Windows 風操作
vim.keymap.set('n', '<C-a>', 'ggVG',     noremap_silent)
vim.keymap.set('i', '<C-a>', '<Esc>ggVG', noremap_silent)
vim.keymap.set('n', '<C-z>', 'u',         noremap_silent)
vim.keymap.set('i', '<C-z>', '<C-o>u',    noremap_silent)
vim.keymap.set('v', '<C-z>', '<Esc>u',    noremap_silent)
vim.keymap.set('n', '<C-y>', '<C-r>',     noremap_silent)
vim.keymap.set('i', '<C-y>', '<C-o><C-r>', noremap_silent)
vim.keymap.set('v', '<C-x>', 'x',         noremap_silent)
vim.keymap.set('v', '<C-c>', 'y',         noremap_silent)
vim.keymap.set('i', '<C-v>', '<C-r>*',    noremap_silent)
vim.keymap.set('v', '<C-v>', '"0p',       noremap_silent)
-- <C-q> で矩形選択（ターミナルが <C-v> を横取りする場合の代替）
vim.keymap.set('n', '<C-q>', '<C-v>', { noremap = true })

-- ジャンプ履歴（前/次に閲覧していた位置へ移動。ブラウザの戻る/進むに相当）
vim.keymap.set('n', '<C-Left>',  '<C-o>', noremap_silent)
vim.keymap.set('n', '<C-Right>', '<C-i>', noremap_silent)

-- ウィンドウ移動
vim.keymap.set('n', '<S-Tab>', '<C-w>w', noremap_silent)

-- プラグイン用マッピング
vim.keymap.set('n', ',st', ':Gstatus<CR>', noremap_silent)
vim.keymap.set('n', ',df', ':Gdiff<CR>',   noremap_silent)
vim.keymap.set('n', ',bl', ':Gblame<CR>',  noremap_silent)

-- ==========================================================
-- 5. 自動保存
-- ==========================================================
vim.api.nvim_create_autocmd({ 'TextChanged', 'InsertLeave' }, {
  pattern = '*',
  callback = function()
    if vim.bo.modifiable and vim.bo.buftype == '' and vim.fn.expand('%') ~= '' then
      vim.cmd('silent! write')
    end
  end,
})

-- ==========================================================
-- 6. OSC 52 クリップボード (SSH 接続時)
-- ==========================================================
vim.opt.clipboard:append('unnamedplus')

if vim.env.SSH_CONNECTION or vim.env.SSH_CLIENT or vim.env.SSH_TTY then
  local function osc52_copy(lines)
    local str    = table.concat(lines, '\n')
    local base64 = vim.fn.system('base64 | tr -d "\\n"', str)
    local osc52  = '\027]52;c;' .. base64 .. '\007'
    if vim.env.TMUX then
      osc52 = '\027Ptmux;\027' .. osc52 .. '\027\\'
    end
    vim.fn.writefile({ osc52 }, '/dev/stderr', 'b')
  end

  vim.g.clipboard = {
    name  = 'osc52-custom',
    copy  = {
      ['+'] = osc52_copy,
      ['*'] = osc52_copy,
    },
    paste = {
      ['+'] = function() return { vim.fn.getreg('+'), vim.fn.getregtype('+') } end,
      ['*'] = function() return { vim.fn.getreg('*'), vim.fn.getregtype('*') } end,
    },
  }
  vim.opt.clipboard:append('unnamedplus')
end

-- ==========================================================
-- 7. macOS専用設定 (他OSでは本セクションごと除外可能)
-- ==========================================================
if vim.fn.has('mac') == 1 then
  -- IME自動切替: InsertLeave(挿入モード終了)・WinLeave(分割ウィンドウ間移動)で英数入力ソース(ABC)へ切替
  -- 要 macism (brew tap laishulu/homebrew && brew install macism)
  if vim.fn.executable('macism') == 1 then
    vim.api.nvim_create_autocmd({ 'InsertLeave', 'WinLeave' }, {
      pattern = '*',
      callback = function()
        vim.fn.system('macism com.apple.keylayout.ABC')
      end,
    })
  end
end
