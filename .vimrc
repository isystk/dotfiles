" ==========================================================
" 1. 基本設定 (Encoding, etc.)
" ==========================================================
set encoding=utf-8
scriptencoding utf-8
set fileencoding=utf-8
set fileencodings=ucs-boms,utf-8,euc-jp,cp932
set fileformats=unix,dos,mac
set ambiwidth=double

" ==========================================================
" 2. vim-plug (Plugin Management)
" ==========================================================
" 自動インストール設定
if empty(glob('~/.vim/autoload/plug.vim'))
  silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

function! s:is_plugged(name)
  return exists('g:plugs') && has_key(g:plugs, a:name) && isdirectory(g:plugs[a:name].dir)
endfunction

call plug#begin('~/.vim/plugged')

" 外観・UI
Plug 'tomasr/molokai'
Plug 'itchyny/lightline.vim'
Plug 'Yggdroot/indentLine'
Plug 'bronson/vim-trailing-whitespace'

" 開発サポート
Plug 'vim-syntastic/syntastic'
Plug 'posva/vim-vue'
Plug 'Quramy/tsuquyomi'
Plug 'alvan/vim-closetag'
Plug 'airblade/vim-gitgutter'
Plug 'tpope/vim-fugitive'

" ファイラー・検索
Plug 'scrooloose/nerdtree'
Plug 'Shougo/unite.vim'
Plug 'Shougo/neomru.vim'

" 入力補完 (deoplete)
if has('nvim')
  Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
else
  Plug 'Shougo/deoplete.nvim'
  Plug 'roxma/nvim-yarp'
  Plug 'roxma/vim-hug-neovim-rpc'
endif

call plug#end()

" ==========================================================
" 3. 外観設定 (Molokaiの色化け対策含む)
" ==========================================================
set t_Co=256
syntax enable

if s:is_plugged("molokai")
    " 256色ターミナルでの色化けを防ぐ
    let g:molokai_original = 1
    let g:re_visual_selection = 0

    " 背景色がNERDTree等で変わるのを防ぐ
    autocmd ColorScheme molokai highlight Normal ctermbg=none
    
    " カスタムハイライト
    autocmd ColorScheme molokai highlight Comment ctermfg=22 guifg=#008800
    autocmd ColorScheme molokai highlight Visual ctermfg=8 guifg=#EEEEEE
    colorscheme molokai
endif

set laststatus=2
set number
set cursorline
set virtualedit=block

" ==========================================================
" 4. 挙動・操作設定
" ==========================================================
" インデント
set expandtab
set tabstop=2
set softtabstop=2
set shiftwidth=2
set autoindent
set smartindent

" 検索
set incsearch
set ignorecase
set smartcase
set hlsearch

" コマンド
set wildmenu
set history=5000
set backspace=indent,eol,start
set mouse=a " マウス操作を有効化（スクロール等が楽になります）

" クリップボードをシステムと同期
set clipboard+=unnamedplus,unnamed

" ==========================================================
" 5. キーマッピング
" ==========================================================
" 検索ハイライト解除 (ESC 2回)
nnoremap <silent><Esc><Esc> :<C-u>set nohlsearch!<CR>

" カーソル下の単語を置換準備 (#)
nnoremap <silent> <Space><Space> :let @/ = '\<' . expand('<cword>') . '\>'<CR>:set hlsearch<CR>
nmap # <Space><Space>:%s/<C-r>///g<Left><Left>

" 対応ペアへジャンプ (TAB)
nnoremap <Tab> %

" インデント (TAB)
vnoremap <Tab> >gv
vnoremap <S-Tab> <gv

" 連続ペースト (レジスタ0を使用)
vnoremap p "0p
vnoremap <S-p> "0p

" インサートモード移動
inoremap <C-k> <Up>
inoremap <C-j> <Down>
inoremap <C-h> <Left>
inoremap <C-l> <Right>

" --- Windows風操作 ---

" [Ctrl]+[a]：全選択 (数字の+1機能は使えなくなります)
nnoremap <C-a> ggVG
inoremap <C-a> <Esc>ggVG

" [Ctrl]+[z]：戻る (Undo)
" noremap ではなく nnoremap を推奨（再帰ループ防止）
nnoremap <C-z> u
inoremap <C-z> <C-o>u
vnoremap <C-z> <Esc>u

" [Ctrl]+[y]：やり直し (Redo)
nnoremap <C-y> <C-r>
inoremap <C-y> <C-o><C-r>

" ビジュアルモードで [Ctrl]+[x]：切り取り
vnoremap <C-x> x

" ビジュアルモードで [Ctrl]+[c]：コピー
vnoremap <C-c> "+y

" [Ctrl]+[v]：貼り付け
" インサートモードで貼り付けた後、そのまま入力を続けられるように調整
inoremap <C-v> <C-r>*
"nnoremap <C-v> P
vnoremap <C-v> "0p

" ==========================================================
" 6. 各プラグインの個別設定
" ==========================================================
" NERDTree
let NERDTreeShowHidden = 1
augroup NERDTreeSetting
    autocmd!
    " 1. Vim起動時に常にNERDTreeを開く
    autocmd VimEnter * NERDTree
    " 2. 起動時にカーソルをファイル編集画面側に移動させる（ツリー側ではなく）
    autocmd VimEnter * wincmd p
    " 3. 他のバッファをすべて閉じて、NERDTreeだけが残ったらVimを終了する
    autocmd BufEnter * if (winnr("$") == 1 && exists("b:NERDTree") && b:NERDTree.isTabTree()) | q | endif
augroup END

" Ctrl+n でツリーの表示/非表示を切り替える
nnoremap <C-n> :NERDTreeToggle<CR>


" Unite.vim
nnoremap <C-U><C-F> :Unite -buffer-name=file file<CR>
nnoremap <C-U><C-R> :Unite file_mru buffer<CR>

" Deoplete
let g:deoplete#enable_at_startup = 1
set completeopt+=noinsert

" Closetag
let g:closetag_filenames = '*.html,*.xhtml,*.phtml,*.erb,*.php,*.vue'

" Gitfugitive
nnoremap ,st :Gstatus<CR>
nnoremap ,df :Gdiff<CR>
nnoremap ,bl :Gblame<CR>
