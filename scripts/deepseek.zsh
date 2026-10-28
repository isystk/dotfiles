# Claude Code 本体の接続先を、現在のシェルだけ DeepSeek へ切り替える。
# このファイルは source される前提（.zshrc の alias deepseek="source ..."）。
# 子プロセスでは親シェルの環境変数を変更できないため、この処理だけは source で実行する。
# 使い方: deepseek [on|off|status]   （引数なしは on）
#
# 環境変数:
#   DEEPSEEK_CC_MODEL / DEEPSEEK_MODEL  設定するモデル名（既定 deepseek-flash）
#   DEEPSEEK_API_KEY                    APIキー（未設定なら DEEPSEEK_API_KEY_FILE を読む）
#   DEEPSEEK_API_KEY_FILE               キーのファイル（既定 ~/.config/deepseek/api_key）

_deepseek_main() {
    local model key_file key
    case "${1:-on}" in

        # Anthropic（既定）へ戻す。実行中の claude には反映されないので再起動が必要。
        off|disable)
            unset ANTHROPIC_BASE_URL ANTHROPIC_API_KEY ANTHROPIC_MODEL
            unset ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL
            unset CLAUDE_CODE_SUBAGENT_MODEL
            unset -f claude 2>/dev/null
            echo "Anthropic（既定）へ戻した（現在のシェルのみ）。claude の再起動が必要"
            ;;

        # 現在の切替状態を表示
        status)
            if [[ -f "$HOME/.setenv.local" ]] && grep -qF '# >>> claude-deepseek >>>' "$HOME/.setenv.local"; then
                echo "設定ファイル: 旧スキルのブロックあり（~/.setenv.local）。削除するまで新しいシェルも DeepSeek で起動する"
            else
                echo "設定ファイル: 旧スキルのブロックなし"
            fi
            echo "現在のシェル: ANTHROPIC_BASE_URL=${ANTHROPIC_BASE_URL:-(未設定)}"
            echo "現在のシェル: ANTHROPIC_MODEL=${ANTHROPIC_MODEL:-(未設定)}"
            if (( ${+functions[claude]} )); then
                echo "現在のシェル: claude ラッパーあり（機密の環境変数を除いて起動）"
            else
                echo "現在のシェル: claude ラッパーなし"
            fi
            ;;

        # DeepSeek へ切替（現在のシェルのみ。実行中の claude には反映されないので再起動が必要）
        on|enable)
            model="${DEEPSEEK_CC_MODEL:-${DEEPSEEK_MODEL:-deepseek-flash}}"
            key_file="${DEEPSEEK_API_KEY_FILE:-$HOME/.config/deepseek/api_key}"
            if [[ -n "${DEEPSEEK_API_KEY:-}" ]]; then
                export ANTHROPIC_API_KEY="$DEEPSEEK_API_KEY"
            elif [[ -r "$key_file" ]]; then
                key="$(< "$key_file")"
                export ANTHROPIC_API_KEY="${key//[[:space:]]/}"
            else
                echo "APIキーが見つかりません: DEEPSEEK_API_KEY を export するか $key_file に保存する" >&2
                return 3
            fi
            export ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
            export ANTHROPIC_MODEL="$model"
            export ANTHROPIC_DEFAULT_OPUS_MODEL="$model"
            export ANTHROPIC_DEFAULT_SONNET_MODEL="$model"
            export ANTHROPIC_DEFAULT_HAIKU_MODEL="$model"
            export CLAUDE_CODE_SUBAGENT_MODEL="$model"

            # 機密の環境変数を claude プロセスへ渡さない（Bash 子プロセス経由で DeepSeek へ送られるのを防ぐ）
            claude() {
                local v
                local -a a
                a=()
                while IFS= read -r v; do
                    case "$v" in
                        DEEPSEEK_API_KEY|ANTHROPIC_*|CLAUDE_*) ;;
                        *KEY*|*TOKEN*|*SECRET*|*PASSWORD*) a+=(-u "$v") ;;
                    esac
                done < <(command env | cut -d= -f1)
                command env "${a[@]}" claude "$@"
            }
            echo "DeepSeek へ切替した（現在のシェルのみ、モデル: $model）。claude の再起動が必要"
            ;;

        *)
            echo "usage: deepseek [on|off|status]" >&2
            return 2
            ;;
    esac
}

# 最後の式にすることで source の終了コードがそのまま deepseek の終了コードになる
_deepseek_main "$@"
