--[[
Neovim設定

前提:
- lazy.nvim: 初回起動時に自動インストール
- 外部コマンド: git / prettier / pint(PHP) / eslint (フォーマット・Lintに使用)
- ripgrep(rg) → ファイル検索(<C-p> / <Space><Space> / <leader>fg)に使用
- lazygit (https://github.com/jesseduffield/lazygit) → lazygit.nvim (<leader>g等) に使用
- Nerd Font (nvim-web-devicons のアイコン表示に必要)
- macOS: macism (brew tap laishulu/homebrew && brew install macism) → IME自動切替に使用
- WSL: windows/tools/ime-watcher.ps1 (Windows側で常駐起動) → IME自動切替に使用

主要キーマップ (<leader> = Space):
- <C-n> / <leader>e        ファイルツリー切替 (neo-tree)
- <C-p> / <Space><Space>   ファイル検索 (telescope)
- <C-f>                    ファイル内検索 (telescope)
- <C-r>                    置換 (ノーマル: バッファ全体 / ビジュアル: 選択範囲)
- <leader>fg               全文検索
- <leader>fb               バッファ一覧
- <leader>tc               ターミナル切替
- <leader>ts (visual)      選択範囲をターミナルへ送信
- <leader>ac               ClaudeCode切替
- <leader>g / ,st          LazyGit起動
- <leader>G                LazyGit起動 (現在ファイルの履歴に絞り込み)
- <S-Tab>                  ウィンドウ移動
- gd / K / gr / <leader>rn / <leader>ca   LSP: 定義 / hover / 参照 / rename / code action

構成:
1. 基本設定  2. プラグイン(lazy.nvim)  3. 外観・挙動  4. キーマッピング
5. 自動保存  6. OSC52クリップボード(SSH接続時)  7. macOS専用設定  8. WSL専用設定

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

-- OSのファイルマネージャーでパスを開く(mac: open / WSL: explorer.exe)。
-- `open`はmacOS専用コマンドのためWSLには存在せず無反応になる。WSLではWindows側パスへ
-- 変換(wslpath -w)した上でexplorer.exeへ渡す(explorer.exeは正常時も非0終了することがあるため終了コードは無視)
local function open_in_explorer(path)
  local abs_path = vim.fn.fnamemodify(path, ':p')
  if vim.fn.has('mac') == 1 then
    vim.fn.system('open ' .. vim.fn.shellescape(abs_path))
  elseif vim.env.WSL_DISTRO_NAME then
    local win_path = vim.fn.system('wslpath -w ' .. vim.fn.shellescape(abs_path)):gsub('\n', '')
    vim.fn.system('explorer.exe ' .. vim.fn.shellescape(win_path))
  else
    vim.notify('Open Explorer: mac/WSL以外は未対応', vim.log.levels.WARN)
  end
end

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
    -- '**/'を付与し、gitignore流のルート限定マッチではなく全階層のnode_modules/vendor等を除外する
    '--glob', '!**/.git/*', '--glob', '!**/.history/*', '--glob', '!**/node_modules/*', '--glob', '!**/vendor/*',
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

  -- 全ファイル一覧は初回入力時のみrg実行しキャッシュ(入力毎の再実行を避ける)。
  -- systemlist(同期実行)はUIスレッドをブロックするため、jobstartで非同期実行しfinderをrefreshする
  local all_files_cache = nil
  local job_running = false
  local current_picker

  local function start_all_files_job()
    if job_running or all_files_cache then
      return
    end
    job_running = true
    vim.fn.jobstart(find_command, {
      stdout_buffered = true,
      on_stdout = function(_, data)
        if data then
          all_files_cache = vim.tbl_filter(function(line) return line ~= '' end, data)
        end
      end,
      on_exit = function()
        job_running = false
        if current_picker and not current_picker.closed and all_files_cache then
          current_picker:refresh(finders.new_table({
            results = all_files_cache,
            entry_maker = function(entry)
              return { value = entry, display = entry, ordinal = entry }
            end,
          }), { reset_prompt = false })
        end
      end,
    })
  end

  current_picker = pickers.new({}, {
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
        if all_files_cache then
          return all_files_cache
        end
        start_all_files_job()
        return {}
      end,
    }),
    sorter = conf.file_sorter({}),
    previewer = conf.file_previewer({}),
    on_input_filter_cb = function(query)
      return { prompt = query:gsub('\\', '/') }
    end,
  })
  current_picker:find()
end

-- ビジュアル選択中の<C-f>は、選択テキストを検索クエリへ自動セットしてファイル内検索を開く
local function telescope_fuzzy_find_with_selection()
  vim.cmd('normal! "vy')
  local selected = vim.fn.getreg('v')
  require('telescope.builtin').current_buffer_fuzzy_find({ default_text = selected })
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
  {
    'MeanderingProgrammer/render-markdown.nvim',
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' },
    ft = 'markdown',
    opts = {},
  },

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

      local ts_filetypes = { 'javascript', 'typescript', 'tsx', 'php', 'html', 'css', 'json', 'lua', 'vim', 'blade', 'markdown', 'markdown_inline' }
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
  {
    'kdheepak/lazygit.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    cmd = { 'LazyGit', 'LazyGitFilterCurrentFile' },
    keys = {
      { ',st', '<cmd>LazyGit<cr>', desc = 'LazyGit起動' },
      { '<leader>g', '<cmd>LazyGit<cr>', desc = 'LazyGit起動' },
      { '<leader>G', '<cmd>LazyGitFilterCurrentFile<cr>', desc = 'LazyGit(現在ファイルの履歴)' },
    },
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
          vim.keymap.set('n', 'gr', function()
            require('telescope.builtin').lsp_references()
          end, opts)
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
      -- Markdown等でvisual選択中、カーソル移動毎の高頻度selection_changed送信が
      -- WebSocket ECONNRESET(Client read error)を誘発するため、送信間隔を広げて緩和する
      -- (track_selection=falseにすると<leader>as手動送信自体が無効化されるため使えない)
      visual_demotion_delay_ms = 500,
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
    -- <C-n>/<leader>eはgit_statusパネルも連動させるためconfig内でtoggle_neotree_panelsへ紐付ける
    opts = {
      close_if_last_window = true,
      filesystem = {
        filtered_items = {
          visible = true, -- 隠しファイルも表示 (旧NERDTreeShowHidden相当)
        },
      },
      git_status = {
        window = {
          position = 'current', -- filesystemウィンドウ下の自前分割に埋め込む(position='left'は1タブ1枠のため重ね表示不可)
          -- position='current'時、標準の"open"はget_appropriate_windowを経由せず
          -- カレントウィンドウ(=git_statusパネル自身)にファイルを開いてしまうため、
          -- ファイル表示用ウィンドウへ明示的に開く独自コマンドへ差し替える
          mappings = {
            ['<cr>'] = 'open_in_file_win',
            ['<2-LeftMouse>'] = 'open_in_file_win',
          },
        },
        commands = {
          open_in_file_win = function(state)
            local node = state.tree:get_node()
            if not node then
              return
            end
            if node.type == 'directory' then
              -- フォルダはファイルウィンドウへ逃がさず通常のtoggle_node(開閉)に委譲
              require('neo-tree.sources.common.commands').toggle_node(state)
              return
            end
            local path = node.path or node:get_id()

            -- 起動時にマークした専用ファイルウィンドウがあれば優先
            local target_win
            for _, win in ipairs(vim.api.nvim_list_wins()) do
              if vim.api.nvim_win_is_valid(win) and vim.w[win].is_file_win then
                target_win = win
                break
              end
            end
            -- 無ければneo-tree・ターミナル以外の最初の通常ウィンドウを使う
            if not target_win then
              for _, win in ipairs(vim.api.nvim_list_wins()) do
                local buf = vim.api.nvim_win_get_buf(win)
                if vim.bo[buf].filetype ~= 'neo-tree' and vim.bo[buf].buftype == '' then
                  target_win = win
                  break
                end
              end
            end

            -- 通常表示ではなく変更差分(HEADとの差分)をdiffバッファとして表示する。
            -- 追跡外ファイルはHEADとの差分が取れないため、新規ファイル全体を追加差分として生成する。
            local diff_output = vim.fn.systemlist({ 'git', 'diff', 'HEAD', '--', path })
            if #diff_output == 0 then
              diff_output = vim.fn.systemlist({ 'git', 'diff', '--no-index', '--', '/dev/null', path })
            end

            -- diff生成中(systemlist)や別バッファのBufDelete等の副作用でウィンドウが
            -- 閉じられ、ここまでの間にtarget_winが無効化されるケースがあるため直前に再検証する
            if target_win and not vim.api.nvim_win_is_valid(target_win) then
              target_win = nil
            end

            if target_win then
              vim.api.nvim_set_current_win(target_win)
            end

            if #diff_output == 0 then
              -- 差分が取得できない場合(変更なしファイル等)は通常表示にフォールバック
              vim.cmd('edit ' .. vim.fn.fnameescape(path))
              return
            end

            local buf_name = 'diff://' .. path
            local existing = vim.fn.bufnr(buf_name)
            if existing ~= -1 then
              vim.api.nvim_buf_delete(existing, { force = true })
            end
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_name(buf, buf_name)
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, diff_output)
            vim.bo[buf].filetype = 'diff'
            vim.bo[buf].buftype = 'nofile'
            vim.bo[buf].bufhidden = 'wipe'
            vim.bo[buf].swapfile = false
            vim.bo[buf].modifiable = false
            if target_win and not vim.api.nvim_win_is_valid(target_win) then
              target_win = nil
            end
            vim.api.nvim_win_set_buf(target_win or 0, buf)

            -- filesystemパネル側でも同じファイルをreveal(ハイライト)する。
            -- action='focus'はneo-treeウィンドウへフォーカスを奪うため、reveal後は
            -- diffバッファ側のウィンドウへフォーカスを戻す
            local diff_win = vim.api.nvim_get_current_win()
            local ok_cmd, neotree_command = pcall(require, 'neo-tree.command')
            if ok_cmd then
              neotree_command.execute({
                action = 'focus',
                source = 'filesystem',
                position = 'left',
                reveal = true,
                reveal_file = path,
                reveal_force_cwd = true,
              })
            end
            if vim.api.nvim_win_is_valid(diff_win) then
              vim.api.nvim_set_current_win(diff_win)
            end
          end,
        },
      },
    },
    config = function(_, opts)
      require('neo-tree').setup(opts)

      -- filesystem(左サイドバー) + git_status(その下の分割、g:panels=1時のみ)を開く。
      -- git_statusはposition='current'指定のため、事前にfilesystem下へ分割を作ってから埋め込む
      local function open_neotree_panels()
        local manager = require('neo-tree.sources.manager')
        vim.cmd('Neotree show')
        local fs_state = manager.get_state('filesystem')
        if not (fs_state and fs_state.winid and vim.api.nvim_win_is_valid(fs_state.winid)) then
          return
        end
        if vim.g.panels ~= 1 then
          return
        end
        local gs_state = manager.get_state('git_status')
        if gs_state and gs_state.winid and vim.api.nvim_win_is_valid(gs_state.winid) then
          return -- 既に開いている
        end
        vim.api.nvim_set_current_win(fs_state.winid)
        vim.cmd('belowright split')
        -- splitはfilesystemのneo-treeバッファをそのまま複製するため、filetype='neo-tree'のまま
        -- 'Neotree position=current'を実行すると、neo-tree側の安全策で継承中のposition('left')へ
        -- 上書きされてしまう。空バッファへ逃がしてから呼び出す
        vim.cmd('enew')
        vim.api.nvim_win_set_height(0, 15)
        -- dirを渡さないとstate.pathが未設定のままになり、manager.refresh()の対象外
        -- (state.path判定)になって:w保存時の自動リフレッシュが効かなくなる
        require('neo-tree.command').execute({
          action = 'show',
          source = 'git_status',
          position = 'current',
          dir = fs_state.path or vim.fn.getcwd(),
        })
        vim.api.nvim_set_current_win(fs_state.winid)
      end

      -- filesystem・git_status(左サイドバー内)を一括で開閉するトグル。
      -- 個別にNeotree toggleすると片方だけ開閉されずレイアウトが崩れるため
      local function toggle_neotree_panels()
        local manager = require('neo-tree.sources.manager')
        local fs_state = manager.get_state('filesystem')
        if fs_state and fs_state.winid and vim.api.nvim_win_is_valid(fs_state.winid) then
          local gs_state = manager.get_state('git_status')
          if gs_state and gs_state.winid and vim.api.nvim_win_is_valid(gs_state.winid) then
            vim.api.nvim_win_close(gs_state.winid, false)
          end
          vim.cmd('Neotree close')
        else
          open_neotree_panels()
        end
      end
      vim.keymap.set('n', '<C-n>', toggle_neotree_panels, { desc = 'ファイルツリー切替' })
      vim.keymap.set('n', '<leader>e', toggle_neotree_panels, { desc = 'ファイルツリー切替' })
      _G.__open_neotree_panels = open_neotree_panels

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

          -- git_statusパネルにフォーカスした瞬間にリフレッシュ(定期タイマーより即時性を優先)
          vim.api.nvim_create_autocmd('WinEnter', {
            group = augroup,
            buffer = args.buf,
            callback = function()
              local ok, source = pcall(vim.api.nvim_buf_get_var, args.buf, 'neo_tree_source')
              if ok and source == 'git_status' then
                require('neo-tree.sources.git_status').refresh()
              end
            end,
          })
        end,
      })
      vim.api.nvim_create_autocmd('VimEnter', {
        group = augroup,
        callback = function()
          -- 起動時 --cmd "let g:panels=1" 指定時のみ複数パネル(ClaudeCode+ターミナル+Neotree)を展開する
          if vim.g.panels ~= 1 then
            _G.__open_neotree_panels()
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
          _G.__open_neotree_panels()

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
          -- カレントのneo-tree cwd配下のファイルのみreveal。cwd外のファイルはcwdを
          -- 強制変更せず、確認ダイアログも出さず、revealだけスキップしてツリーはそのまま保つ
          local fs_state = require('neo-tree.sources.manager').get_state('filesystem')
          require('neo-tree.command').execute({
            action = 'show',
            reveal = true,
            reveal_force_cwd = false,
            dir = fs_state and fs_state.path,
          })
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
      { '<C-f>', '<cmd>Telescope current_buffer_fuzzy_find<cr>', desc = 'ファイル内検索' },
      { '<C-f>', telescope_fuzzy_find_with_selection, mode = 'v', desc = 'ファイル内検索(選択範囲)' },
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

    -- render-markdown.nvim: デフォルトはtreesitterの@markup系グループにリンクされるが、
    -- molokaiでは定義が薄く見出し/コードブロックのコントラストが弱いため明示的に上書きする
    vim.cmd('highlight RenderMarkdownH1Bg guibg=#3c3d37 guifg=#f92672 gui=bold')
    vim.cmd('highlight RenderMarkdownH2Bg guibg=#3c3d37 guifg=#a6e22e gui=bold')
    vim.cmd('highlight RenderMarkdownH3Bg guibg=#3c3d37 guifg=#66d9ef gui=bold')
    vim.cmd('highlight RenderMarkdownH4Bg guibg=#3c3d37 guifg=#e6db74 gui=bold')
    vim.cmd('highlight RenderMarkdownH5Bg guibg=#3c3d37 guifg=#fd971f gui=bold')
    vim.cmd('highlight RenderMarkdownH6Bg guibg=#3c3d37 guifg=#ae81ff gui=bold')
    vim.cmd('highlight RenderMarkdownCode guibg=#272822')
    vim.cmd('highlight RenderMarkdownCodeInline guibg=#3c3d37 guifg=#e6db74')
    vim.cmd('highlight RenderMarkdownBullet guifg=#a6e22e')
    vim.cmd('highlight RenderMarkdownQuote guifg=#75715e')
    vim.cmd('highlight RenderMarkdownDash guifg=#75715e')
    vim.cmd('highlight RenderMarkdownLink guifg=#66d9ef gui=underline')
    vim.cmd('highlight RenderMarkdownSign guifg=#75715e')
    vim.cmd('highlight RenderMarkdownTableHead guifg=#66d9ef')
    vim.cmd('highlight RenderMarkdownTableRow guifg=#f8f8f2')
    vim.cmd('highlight RenderMarkdownTableFill guifg=#75715e')
  end,
})

vim.g.molokai_original    = 1
vim.g.re_visual_selection = 0
vim.cmd('colorscheme molokai')

-- ==========================================================
-- 3.5 右クリックメニュー(PopUp)のカスタマイズ
-- ==========================================================
-- 既定のPopUpメニューは標準ランタイムのmenu.vimで定義され、右クリック初回表示時に遅延読込される。
-- 事前にruntimeしてロードした上で、既定メニューを丸ごと外し実用的な構成に作り直す。
vim.cmd('runtime! menu.vim')
vim.cmd('silent! aunmenu PopUp')

-- menu選択時のコールバックはpopup表示中(textlock)の同期コンテキストで実行され、その中で
-- テキスト変更・ウィンドウ生成を行うとE565(Not allowed to change text or change window)になるため、
-- 実処理は必ずvim.schedule()でtextlock解除後まで遅延させる。
-- (menuコマンドはVimscript文字列で関数呼び出しを書けないため、lua関数はグローバル経由で呼ぶ)
_G.__popup_actions = {
  inspect = function() vim.cmd('Inspect') end,
  go_to_definition = function() vim.lsp.buf.definition() end,
  references = function() require('telescope.builtin').lsp_references() end,
  hover = function() vim.lsp.buf.hover() end,
  rename = function() vim.lsp.buf.rename() end,
  code_action = function() vim.lsp.buf.code_action() end,
  document_symbols = function() require('telescope.builtin').lsp_document_symbols() end,
  show_diagnostics = function() vim.cmd('Trouble diagnostics toggle') end,
  grep_word = function()
    local word = vim.fn.expand('<cword>')
    require('telescope.builtin').live_grep({ default_text = word })
  end,
  yank_path_line = function()
    local path = vim.fn.expand('%:.')
    local line = vim.api.nvim_win_get_cursor(0)[1]
    local text = string.format('%s:%d', path, line)
    vim.fn.setreg('+', text)
    vim.fn.setreg('"', text)
    vim.notify('yank: ' .. text)
  end,
  reveal_in_tree = function() vim.cmd('Neotree reveal') end,
  -- Open Explorer/Run Format/Run Test: 対象は現在編集中ファイルの相対パス
  open_explorer = function()
    open_in_explorer(vim.fn.expand('%:.'))
  end,
  -- Run Format/Run Test は `make format <path>` / `make test <path>` をカレントディレクトリの
  -- Makefile経由で実行する想定。対象パス配下(または上位)にMakefileが存在しない場合は動作しない
  run_format = function()
    send_text_to_terminal('make format ' .. vim.fn.shellescape(vim.fn.expand('%:.')) .. '\n')
  end,
  run_test = function()
    send_text_to_terminal('make test ' .. vim.fn.shellescape(vim.fn.expand('%:.')) .. '\n')
  end,
  paste = function() vim.cmd('normal! "+gP') end,
  select_all = function() vim.cmd('normal! ggVG') end,
  -- Stage/UnstageはLazyGitの操作段数が多く実用的でないため、gitコマンドを直接叩く
  git_stage_file = function() __git_file_cmd('add') end,
  git_unstage_file = function() __git_file_cmd('reset') end,
  -- Diff/Blame/HistoryはLazyGit経由(fugitive等を未導入のため)。開いた後はLazyGit側の
  -- キー操作(コミット選択→d でdiff、b でblame等)で該当情報まで辿る
  git_diff_file = function() vim.cmd('LazyGit') end,
  git_blame_line = function() vim.cmd('LazyGitFilterCurrentFile') end,
  git_file_history = function() vim.cmd('LazyGitFilterCurrentFile') end,
  lazygit = function() vim.cmd('LazyGit') end,
  cheatsheet = function() _G.__show_cheatsheet() end,
}
_G.__popup_run = function(name)
  local fn = _G.__popup_actions[name]
  if fn then
    vim.schedule(fn)
  end
end

-- カレントファイルに対して`git -C <dir> <subcmd> -- <file>`を実行する共通ヘルパー
_G.__git_file_cmd = function(subcmd)
  local file = vim.fn.expand('%:p')
  if file == '' then
    vim.notify('保存されたファイルがありません', vim.log.levels.WARN)
    return
  end
  local dir = vim.fn.fnamemodify(file, ':h')
  local cmd = string.format('git -C %s %s -- %s', vim.fn.shellescape(dir), subcmd, vim.fn.shellescape(file))
  local out = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    vim.notify('git ' .. subcmd .. ' failed: ' .. out, vim.log.levels.ERROR)
  else
    vim.notify('git ' .. subcmd .. ': ' .. vim.fn.fnamemodify(file, ':t'))
  end
end

vim.cmd([[
  nnoremenu 1.10 PopUp.Inspect <Cmd>lua __popup_run('inspect')<CR>
  nnoremenu 1.20 PopUp.-1- <Nop>
  nnoremenu 1.21 PopUp.Go\ to\ Definition <Cmd>lua __popup_run('go_to_definition')<CR>
  nnoremenu 1.22 PopUp.Find\ References <Cmd>lua __popup_run('references')<CR>
  nnoremenu 1.23 PopUp.Hover <Cmd>lua __popup_run('hover')<CR>
  nnoremenu 1.24 PopUp.Rename\ Symbol <Cmd>lua __popup_run('rename')<CR>
  nnoremenu 1.25 PopUp.Code\ Action <Cmd>lua __popup_run('code_action')<CR>
  nnoremenu 1.26 PopUp.Document\ Symbols <Cmd>lua __popup_run('document_symbols')<CR>
  nnoremenu 1.30 PopUp.-2- <Nop>
  nnoremenu 1.31 PopUp.Show\ All\ Diagnostics <Cmd>lua __popup_run('show_diagnostics')<CR>
  nnoremenu 1.40 PopUp.-3- <Nop>
  nnoremenu 1.41 PopUp.Grep\ Word <Cmd>lua __popup_run('grep_word')<CR>
  nnoremenu 1.42 PopUp.Yank\ Path:Line <Cmd>lua __popup_run('yank_path_line')<CR>
  nnoremenu 1.43 PopUp.Reveal\ in\ Tree <Cmd>lua __popup_run('reveal_in_tree')<CR>
  nnoremenu 1.44 PopUp.-3a- <Nop>
  nnoremenu 1.45 PopUp.Open\ Explorer <Cmd>lua __popup_run('open_explorer')<CR>
  nnoremenu 1.46 PopUp.Run\ Format <Cmd>lua __popup_run('run_format')<CR>
  nnoremenu 1.47 PopUp.Run\ Test <Cmd>lua __popup_run('run_test')<CR>
  nnoremenu 1.50 PopUp.-4- <Nop>
  nnoremenu 1.51 PopUp.Paste <Cmd>lua __popup_run('paste')<CR>
  nnoremenu 1.52 PopUp.Select\ All <Cmd>lua __popup_run('select_all')<CR>
  nnoremenu 1.60 PopUp.-5- <Nop>
  nnoremenu 1.61 PopUp.Git:\ Blame\ Line <Cmd>lua __popup_run('git_blame_line')<CR>
  nnoremenu 1.62 PopUp.Git:\ File\ History <Cmd>lua __popup_run('git_file_history')<CR>
  nnoremenu 1.63 PopUp.Git:\ LazyGit <Cmd>lua __popup_run('lazygit')<CR>
  nnoremenu 1.70 PopUp.-6- <Nop>
  nnoremenu 1.71 PopUp.Help <Cmd>lua __popup_run('cheatsheet')<CR>
]])

-- neo-tree用: ファイル操作コマンドをカーソル位置ノードに対して実行する共通ヘルパー(同じくschedule必須)
_G.__neotree_popup_cmd = function(name)
  vim.schedule(function()
    local state = require('neo-tree.sources.manager').get_state('filesystem')
    local ok_fs, fs_commands = pcall(require, 'neo-tree.sources.filesystem.commands')
    local ok_common, common_commands = pcall(require, 'neo-tree.sources.common.commands')
    local fn = (ok_fs and fs_commands[name]) or (ok_common and common_commands[name])
    if fn then
      fn(state)
    end
  end)
end

-- neo-tree用: Open Explorer/Run Format/Run Test。対象はカーソル位置ノードの相対パス。
-- Run Format/Run Test は `make format <path>` / `make test <path>` をカレントディレクトリの
-- Makefile経由で実行する想定。対象パス配下(または上位)にMakefileが存在しない場合は動作しない
_G.__neotree_popup_action = function(name)
  vim.schedule(function()
    local state = require('neo-tree.sources.manager').get_state('filesystem')
    local node = state and state.tree and state.tree:get_node()
    if not node then
      return
    end
    local path = vim.fn.fnamemodify(node.path or node:get_id(), ':.')
    if name == 'copy_path' then
      vim.fn.setreg('+', path)
      vim.fn.setreg('"', path)
      vim.notify('yank: ' .. path)
    elseif name == 'open_explorer' then
      open_in_explorer(path)
    elseif name == 'run_format' then
      send_text_to_terminal('make format ' .. vim.fn.shellescape(path) .. '\n')
    elseif name == 'run_test' then
      send_text_to_terminal('make test ' .. vim.fn.shellescape(path) .. '\n')
    end
  end)
end

-- neo-tree用(git_statusパネル専用): ステージ/アンステージ/リセット。
-- コマンド本体はneo-tree標準のsources/common/commands.lua実装をそのまま使う。
-- git_statusはposition='current'のためstateがwinid単位で管理されており、
-- winid未指定のget_stateだとtree未構築の別state(nil)を掴んでエラーになる
_G.__neotree_git_popup_cmd = function(name)
  local winid = vim.api.nvim_get_current_win()
  vim.schedule(function()
    local state = require('neo-tree.sources.manager').get_state('git_status', nil, winid)
    if name == 'copy_path' then
      local node = state and state.tree and state.tree:get_node()
      if not node then
        return
      end
      local path = vim.fn.fnamemodify(node.path or node:get_id(), ':.')
      vim.fn.setreg('+', path)
      vim.fn.setreg('"', path)
      vim.notify('yank: ' .. path)
      return
    end
    local ok, common_commands = pcall(require, 'neo-tree.sources.common.commands')
    local fn = ok and common_commands[name]
    if fn then
      fn(state)
    end
  end)
end

vim.cmd([[
  nnoremenu 1.10 PopUpNeoTreeGit.Stage\ File <Cmd>lua __neotree_git_popup_cmd('git_add_file')<CR>
  nnoremenu 1.11 PopUpNeoTreeGit.Unstage\ File <Cmd>lua __neotree_git_popup_cmd('git_unstage_file')<CR>
  nnoremenu 1.20 PopUpNeoTreeGit.-1- <Nop>
  nnoremenu 1.21 PopUpNeoTreeGit.Reset\ File <Cmd>lua __neotree_git_popup_cmd('git_revert_file')<CR>
  nnoremenu 1.30 PopUpNeoTreeGit.-2- <Nop>
  nnoremenu 1.31 PopUpNeoTreeGit.Copy\ Path <Cmd>lua __neotree_git_popup_cmd('copy_path')<CR>
]])

vim.cmd([[
  nnoremenu 1.10 PopUpNeoTree.Add\ File <Cmd>lua __neotree_popup_cmd('add')<CR>
  nnoremenu 1.11 PopUpNeoTree.Add\ Directory <Cmd>lua __neotree_popup_cmd('add_directory')<CR>
  nnoremenu 1.20 PopUpNeoTree.-1- <Nop>
  nnoremenu 1.21 PopUpNeoTree.Rename <Cmd>lua __neotree_popup_cmd('rename')<CR>
  nnoremenu 1.22 PopUpNeoTree.Delete <Cmd>lua __neotree_popup_cmd('delete')<CR>
  nnoremenu 1.30 PopUpNeoTree.-2- <Nop>
  nnoremenu 1.31 PopUpNeoTree.Copy\ Path <Cmd>lua __neotree_popup_action('copy_path')<CR>
  nnoremenu 1.32 PopUpNeoTree.Copy\ to\ Clipboard <Cmd>lua __neotree_popup_cmd('copy_to_clipboard')<CR>
  nnoremenu 1.33 PopUpNeoTree.Cut\ to\ Clipboard <Cmd>lua __neotree_popup_cmd('cut_to_clipboard')<CR>
  nnoremenu 1.34 PopUpNeoTree.Paste <Cmd>lua __neotree_popup_cmd('paste_from_clipboard')<CR>
  nnoremenu 1.40 PopUpNeoTree.-3- <Nop>
  nnoremenu 1.41 PopUpNeoTree.Open\ Explorer <Cmd>lua __neotree_popup_action('open_explorer')<CR>
  nnoremenu 1.42 PopUpNeoTree.Run\ Format <Cmd>lua __neotree_popup_action('run_format')<CR>
  nnoremenu 1.43 PopUpNeoTree.Run\ Test <Cmd>lua __neotree_popup_action('run_test')<CR>
]])

-- mousemodelのpopup_setpos任せだとクリック位置へカーソルが移動し切らずGrep Word等が
-- <cword>を取得できない場合があるため、右クリック時に明示的にカーソルを移動してからメニューを開く。
-- neo-treeバッファ上ではファイル操作用の別メニュー(PopUpNeoTree/PopUpNeoTreeGit)を開く。
-- filesystem/git_statusは同じfiletype='neo-tree'のため、バッファ変数neo_tree_sourceで判別する
vim.keymap.set('n', '<RightMouse>', function()
  local mouse = vim.fn.getmousepos()
  if mouse.winid ~= 0 then
    vim.api.nvim_set_current_win(mouse.winid)
    -- ターミナルパネルでは右クリックメニューを出さない(通常の右クリック挙動に任せる)
    if vim.bo.buftype == 'terminal' then
      return
    end
    -- git_statusパネルから開いたdiff表示バッファでも右クリックメニューを出さない
    if vim.api.nvim_buf_get_name(0):match('^diff://') then
      return
    end
    pcall(vim.api.nvim_win_set_cursor, mouse.winid, { mouse.line, math.max(mouse.column - 1, 0) })
  end
  local menu = 'PopUp'
  if vim.bo.filetype == 'neo-tree' then
    local ok, source = pcall(vim.api.nvim_buf_get_var, 0, 'neo_tree_source')
    menu = (ok and source == 'git_status') and 'PopUpNeoTreeGit' or 'PopUpNeoTree'
  end
  vim.cmd('popup ' .. menu)
end, { desc = '右クリックメニュー(カーソル位置確定後に表示)' })

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
vim.keymap.set('n', '<C-S-z>', '<C-r>',     noremap_silent)
vim.keymap.set('i', '<C-S-z>', '<C-o><C-r>', noremap_silent)
vim.keymap.set('v', '<C-S-z>', '<Esc><C-r>', noremap_silent)
vim.keymap.set('v', '<C-x>', 'x',         noremap_silent)
vim.keymap.set('v', '<C-c>', 'y',         noremap_silent)
vim.keymap.set('i', '<C-v>', '<C-r>*',    noremap_silent)
vim.keymap.set('v', '<C-v>', '"0p',       noremap_silent)
-- <C-q> で矩形選択（ターミナルが <C-v> を横取りする場合の代替）
vim.keymap.set('n', '<C-q>', '<C-v>', { noremap = true })

-- 置換（ノーマル: バッファ全体 / ビジュアル: 選択範囲。gcで置換毎に確認）
vim.keymap.set('n', '<C-r>', ':%s//gc<Left><Left><Left>', { noremap = true })

-- ビジュアル選択中の<C-r>は、選択テキストを検索パターンへ自動セットしてから置換欄へ入る
-- (正規表現特殊文字はescapeでエスケープ、複数行選択時の改行は\nへ変換して1パターンにまとめる)
local function visual_replace_with_selection()
  vim.cmd('normal! "vy')
  local selected = vim.fn.getreg('v')
  local pattern = vim.fn.escape(selected, '/\\.*$^~[]'):gsub('\n', '\\n')
  local keys = ':s/' .. pattern .. '//gc<Left><Left><Left>'
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'n', false)
end
vim.keymap.set('v', '<C-r>', visual_replace_with_selection, { desc = '選択範囲を検索欄にセットして置換' })

-- ジャンプ履歴（前/次に閲覧していた位置へ移動。ブラウザの戻る/進むに相当）
vim.keymap.set('n', '<C-Left>',  '<C-o>', noremap_silent)
vim.keymap.set('n', '<C-Right>', '<C-i>', noremap_silent)

-- ウィンドウ移動
vim.keymap.set('n', '<S-Tab>', '<C-w>w', noremap_silent)

-- プラグイン用マッピング
vim.keymap.set('n', ',df', ':Gdiff<CR>',   noremap_silent)
vim.keymap.set('n', ',bl', ':Gblame<CR>',  noremap_silent)

-- チートシート(~/dotfiles/documents/cheatsheet.md)をフロートウィンドウで表示する。
-- 表示中バッファは使い捨て(bufhidden=wipe)にし、q/<Esc>で閉じられるようにする。
-- 右クリックメニュー(PopUp.Cheatsheet)からも呼ぶためグローバル登録する
_G.__show_cheatsheet = function()
  local path = vim.fn.expand('~/dotfiles/documents/cheatsheet.md')
  if vim.fn.filereadable(path) == 0 then
    vim.notify('cheatsheet.mdが見つかりません: ' .. path, vim.log.levels.ERROR)
    return
  end

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' Cheatsheet ',
    title_pos = 'center',
  })
  vim.wo[win].wrap = false

  local close_opts = { buffer = buf, noremap = true, silent = true }
  vim.keymap.set('n', 'q', '<cmd>close<CR>', close_opts)
  vim.keymap.set('n', '<Esc>', '<cmd>close<CR>', close_opts)
end
vim.keymap.set('n', '<leader>?', _G.__show_cheatsheet, { desc = 'チートシートをフロート表示' })

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

-- ==========================================================
-- 8. WSL専用設定 (他OSでは本セクションごと除外可能)
-- ==========================================================
if vim.env.WSL_DISTRO_NAME then
  -- IME自動切替: InsertLeave(挿入モード終了)・WinLeave(分割ウィンドウ間移動)でIMEをオフへ切替
  -- WSLから都度exeを起動する方式(im-select.exe等)はGetForegroundWindowの
  -- 対象がずれ切替が効かないため、Windows側常駐スクリプト(windows/tools/ime-watcher.ps1)が
  -- 監視するトリガーファイルを書き換えるだけにする(プロセス起動不要)
  local ime_trigger_path = (vim.env.HOME or '') .. '/.nvim-ime-off-trigger'
  vim.api.nvim_create_autocmd({ 'InsertLeave', 'WinLeave' }, {
    pattern = '*',
    callback = function()
      pcall(vim.fn.writefile, {}, ime_trigger_path)
    end,
  })

  -- Windows Terminalのブラケットペーストでvisual選択に貼り付ける際、標準処理だと
  -- 選択範囲の削除で無名レジスタが書き換わり、unnamedplus経由でクリップボードも
  -- 汚染されて連続貼り付けができなくなる(2回目以降、直前に選択していたテキストが貼られる)。
  -- visualモード中のペーストだけ、選択範囲をblackholeレジスタで削除してから挿入し回避する。
  -- (Windows TerminalはCtrl+Vをターミナル側で横取りしvimのkeymapを経由しないため、
  -- 4.キーマッピングの<C-v>単体のkeymapでは対処できず、ここでvim.paste自体を上書きする)
  local default_paste = vim.paste
  vim.paste = function(lines, phase)
    local mode = vim.api.nvim_get_mode().mode
    if mode:match('^[vV\22]') and (phase == 1 or phase == -1) then
      vim.cmd('normal! "_d')
      vim.api.nvim_put(lines, 'c', false, true)
      return true
    end
    -- visual以外(cmdlineの`:` `/`入力中等)はNeovim標準実装に委譲する。
    -- nvim_putはバッファへの挿入専用APIのため、丸ごと上書きするとコマンドライン入力中の貼り付けが効かなくなる
    return default_paste(lines, phase)
  end
end
