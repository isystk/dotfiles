# ==============================================================================
#  zsh Configuration (Optimized)
# ==============================================================================

# --- 1. Language & Environment ---
export LANG=ja_JP.UTF-8
export TERM=xterm-256color

# enhancd config
export ENHANCD_FILTER=fzy
export ENHANCD_DISABLE_DOT=1
export ENHANCD_DISABLE_HOME=1

# パスの追加（ユーザーのローカルbinを優先）
export PATH="$HOME/.local/bin:$PATH"

# 共通ユーティリティスクリプトを読み込む
source "$HOME/dotfiles/scripts/utils.sh"

# --- 2. Zinit (Plugin Manager) ---
if [[ ! -f $HOME/.local/share/zinit/zinit.git/zinit.zsh ]]; then
    print -P "%F{33} Installing Zinit..."
    command mkdir -p "$HOME/.local/share/zinit"
    command git clone https://github.com/zdharma-continuum/zinit "$HOME/.local/share/zinit/zinit.git"
fi

source "$HOME/.local/share/zinit/zinit.git/zinit.zsh"
autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit

# 標準的な補完（タブキーなど）を有効にする
autoload -Uz compinit && compinit -C

# --- 3. Plugins ---

# 1. 即時読み込み
zinit lucid for woefe/git-prompt.zsh
zinit lucid for zsh-users/zsh-autosuggestions
zinit lucid for zdharma-continuum/history-search-multi-word

# 2. 遅延読み込み（少し後でも良いもの）
zinit wait'0' lucid for \
    atinit"autoload -Uz compinit; compinit" \
    zsh-users/zsh-completions \
    zdharma-continuum/fast-syntax-highlighting

# 3. 遅延読み込み（1秒後でも良いもの）
zinit wait'1' lucid for \
    b4b4r07/enhancd \
    t413/zsh-background-notify \
    popstas/zsh-command-time

# --- 4. History ---
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt hist_ignore_dups    # 重複を記録しない
setopt hist_reduce_blanks  # 余分な空白を削除
setopt share_history       # 履歴を共有
setopt extended_history    # タイムスタンプを記録

# --- 5. Zsh Options ---
setopt auto_cd              # ディレクトリ名のみで移動
setopt auto_pushd           # cd時にスタックに追加
setopt pushd_ignore_dups    # スタックの重複を避ける
setopt correct              # スペルミス修正
setopt nolistbeep           # ビープ音オフ
setopt list_packed          # 候補を詰めて表示
setopt magic_equal_subst    # 引数内でも補完
setopt nonomatch            # ワイルドカード展開失敗を許容
setopt transient_rprompt    # 右プロンプトを消去

# --- 6. Prompt & Colors ---
autoload -Uz colors && colors
# プロンプト内の色の定義
PROMPT_OK="%{${fg[green]}%}"
PROMPT_ERR="%{${fg[yellow]}%}"
RESET="%{${reset_color}%}"

# プロンプトの構築（前回の終了時刻を表示）
function precmd() {
  local EXIT_STATUS="%(?.${PROMPT_OK}.${PROMPT_ERR})"
  local TIME=$(date "+%H:%M:%S")
  PROMPT="${EXIT_STATUS}${TIME} $ %B${RESET}"
}

# 右プロンプト (Git状態)
RPROMPT='%B%40<..<%1~ %b$(gitprompt)'

# WSL用のGit Prompt調整
if [[ -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
    ZSH_THEME_GIT_PROMPT_PREFIX="["
    ZSH_THEME_GIT_PROMPT_SUFFIX=" ]"
fi

# 補完候補をメニュー形式で選択できるようにする
zstyle ':completion:*:default' menu select=2
export LS_COLORS='di=34:ln=35:so=32:pi=33:ex=31:bd=34;46:cd=34;43'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# --- 7. Aliases & Hash ---
alias ll='ls -alG'
alias ...='cd ../..'
alias ....='cd ../../..'
alias history='history -t "%F %T"'
alias diff='diff --color=auto'
alias copy='nocorrect copy_clipboard'
alias open='nocorrect open_browser'
alias explorer='nocorrect open_explorer'

# --- 8. External Tools ---
# miseの設定
export MISE_TRUSTED_CONFIG_PATHS="$HOME/dotfiles:$HOME/.config/mise"
export MISE_YES=1
if (( $+commands[mise] )); then
  eval "$(mise activate zsh)"
fi
# gemini-cliのテンプレート位置を設定
export GEMINI_CLI_PATH="$HOME/.config/gemini-cli"

# --- 9. OS Specific Settings ---
if [ -n "$IS_MAC" ]; then
    # Macの場合
    _env_file="$HOME/.setenv.mac"
elif [ -n "$IS_WSL" ]; then
    # WSLの場合
    _env_file="$HOME/.setenv.wsl"
else
    # それ以外のLinux（純粋なUbuntuなど）やOS
    _env_file="$HOME/.setenv.linux"
fi
[[ -n "$_env_file" && -f "$_env_file" ]] && . "$_env_file"
# 機密情報はローカルファイルに分離 (このファイルは.gitignoreに含まれる)
[[ -f ~/.setenv.local ]] && . ~/.setenv.local

# --- 10. Editor Settings ---
: "${_EDITOR_PATH:=vim}"
export EDITOR="$_EDITOR_PATH"
export VISUAL="$_EDITOR_PATH"
alias vi="$_EDITOR_PATH"
alias nvim-ide="nvim --cmd 'let g:panels=1'"

# --- 11. Custom Scripts ---
alias run="$HOME/dotfiles/scripts/run.sh"
_run_completion() {
    local script="$HOME/dotfiles/scripts/run.sh"
    [ ! -x "$script" ] && return
    local -a commands
    local line
    while IFS= read -r line; do
        line=$(echo "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]{2,}/:/; s/\|[^:]*//')
        [[ "$line" == *:* ]] && commands+=("$line")
    done < <("$script" help 2>/dev/null)
    _describe -t commands 'run commands' commands -Q
}
zinit wait'0' lucid for \
    atinit"compdef _run_completion run; setopt complete_aliases" \
    zdharma-continuum/null

# EDITOR/VISUALに"vi"を含む値(nvimパス等)がセットされていると
# zsh起動時に自動でviinsキーマップになりCtrl+A等のemacsバインドが効かなくなるため、
# 明示的にemacsキーマップを指定する
bindkey -e

