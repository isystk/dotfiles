-- init.lua同ディレクトリのフォールバック設定。
-- カレントディレクトリに.nvim.luaが無いプロジェクトで読み込まれる共通デフォルト値。
-- プロジェクト側にMakefile(format/testターゲット)・cheatsheet.mdが無い場合の既定動作。
_G.__format_cmd = 'make format'
_G.__test_cmd = 'make test'
_G.__cheatsheet_path = '~/dotfiles/documents/cheatsheet.md'
