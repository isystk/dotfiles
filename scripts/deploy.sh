#!/bin/sh

# ==============================================================================
# 差分反映スクリプト (git archive-diff 生成用)
# 
# 【処理内容】
#   1. contents/ フォルダ内のファイルをディレクトリ構造を維持して上書きコピー
#   2. deleted.txt に記載されたファイルを環境から削除
# 
# 【使い方】
#   sh deploy.sh
#   ※ 実行時に上書き・削除の確認プロンプト(y/n)が表示されます。
# ==============================================================================

# 1. ファイルの上書きコピー
if [ -d "contents" ]; then
    echo "📦 Updating files..."
    
    # contents/ 内の全ファイルをループ
    for src in $(find contents -type f); do
        dest="./${src#contents/}"
        
        # コピー先が存在する場合のみ確認
        if [ -e "$dest" ]; then
            # 自前でプロンプトを表示 (printf を使うと改行せずに入力を待てる)
            printf "❓ '%s' を上書きしますか？ (y/n): " "$dest"
            read -r answer < /dev/tty
            
            if [ "$answer" != "y" ]; then
                echo "   ⏭️  Skipped: $dest"
                continue
            fi
        fi

        # コピー実行 (ディレクトリがなければ作成)
        mkdir -p "$(dirname "$dest")"
        \cp -f "$src" "$dest"
        echo "   ✅ Updated: $dest"
    done
fi

# 2. ファイルの削除
if [ -f "deleted.txt" ] && [ -s "deleted.txt" ]; then
    echo "🗑️ Removing deleted files..."
    while IFS= read -r file; do
        if [ -e "$file" ]; then
            printf "❓ '%s' を削除しますか？ (y/n): " "$file"
            read -r answer < /dev/tty
            
            if [ "$answer" = "y" ]; then
                \rm -f "$file"
                echo "   ✅ Deleted: $file"
            else
                echo "   ⏭️  Skipped: $file"
            fi
        fi
    done < "deleted.txt"
else
    echo "✨ No files to delete."
fi
