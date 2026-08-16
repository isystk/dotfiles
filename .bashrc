# Zshへの切り替えを促す
if [ -t 0 ] && [ -x "$(command -v zsh)" ]; then
    # すでに Zsh の中にいる場合は実行しない（二重起動防止）
    if [ -z "${ZSH_VERSION:-}" ]; then
        # 5秒以内に入力がなければ（無操作でも）自動的にzshへ切り替える
        read -t 5 -p "Switch to zsh? [Y/n] " answer
        if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
            exec zsh -l
        fi
    fi
fi
