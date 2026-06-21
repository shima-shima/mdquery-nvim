# mdquery.nvim — AI エージェント向けガイダンス

## 概要

Markdown の箇条書きに埋め込まれたメタデータ (`#tag` `@key(val)` `key:val` チェックボックス) を抽出し、独自クエリ言語でフィルタリングする Neovim プラグイン。

姉妹プロジェクト `../mdquery-web/` (Next.js) ・ `../mdquery-vscode/` (VS Code) の Neovim 版。ただしこれらは TypeScript + `remark` を使うのに対し、**本プロジェクトは依存を減らすため Pure Lua でコアロジックを独立実装している**。コードは共有せず、**仕様 (メタデータ構文・クエリ構文) を揃える** 方針。

## 重要: 姉妹プロジェクトとの関係

ルートの `~/.config/shelley/AGENTS.md` に、Web 版・VS Code 版は両方に変更を適用する、というルールがある。**本プロジェクト (Neovim 版) は Lua 独立実装なので、コアロジックの「コピー同期」はできない**。代わりに以下を守る:

- Web / VS Code 版で **クエリ構文やメタデータ抽出仕様が変わったら**、`parser.lua` / `filter.lua` に同等の振る舞いを Lua で実装し直す。
- 振る舞いの一致は `../mdquery-web/src/lib/markdown-parser.ts` / `query-filter.ts` を参照して検証する。

## 現状のスコープ (MVP)

意図的に最小限。以下は **未実装** (Web/VS Code 版にはある):

- 見出しツリー / ネスト子項目 / HTML コメントメタ (`<!-- k:v -->`)
- OR / 否定 `!` / 比較 `>` `<` / 相対日付 `today±N`
- Table / Calendar ビュー、ビュー切替
- サジェスト補完、Saved Filters / プリセット
- マッチ行ハイライト (extmark)、includeChildren トグル、JSON コピー

## ファイルと役割

| ファイル | 役割 |
|---|---|
| `lua/mdquery/parser.lua` | バッファ行 → `item[]` (フラット)。メタデータ抽出。 |
| `lua/mdquery/filter.lua` | クエリ文字列 → 条件リスト (AND) → フィルタ。 |
| `lua/mdquery/ui.lua` | 入力フロート + 結果縦分割 + ジャンプ + インクリメンタル更新。 |
| `lua/mdquery/config.lua` | 設定 (debounce_ms, result_width)。 |
| `lua/mdquery/init.lua` | `setup()` / `open()` エントリ。 |
| `plugin/mdquery.lua` | `:MdQuery` コマンド登録。 |

## テスト方法

`nvim` は headless / tmux で動かせる。

### コアロジックの単体テスト (headless)

```bash
nvim --headless -u NONE -l /tmp/test_mdquery.lua 2>&1
```

`test_mdquery.lua` で `runtimepath` にプラグインを追加し、`parser.parse(lines)` / `filter.filter(items, query)` を直接呼んで `print` 検証する。

### UI の結合テスト (tmux)

```bash
tmux new-session -d -s mq -x 200 -y 45
tmux send-keys -t mq "nvim -u /tmp/init_test.lua /tmp/sample.md" Enter
tmux send-keys -t mq ":MdQuery" Enter
tmux send-keys -t mq "#backend @priority(high)"   # インクリ更新を確認
tmux capture-pane -t mq -p | grep matched
```

`init_test.lua` は `runtimepath` 追加 + `require('mdquery').setup({})`。

## 実装上の注意

- **プロンプトバッファ (`buftype=prompt`)** を使う。バッファ行にはプロンプト接頭辞 (`› `) が含まれるため、クエリ取得時は `prompt_getprompt()` で接頭辞をストリップすること。クエリ復元時は逆に接頭辞を付けてセットする。
- インクリメンタル更新は `TextChangedI`/`TextChanged` autocmd + `vim.loop` タイマーで debounce。
- 結果バッファは `nofile`/非 modifiable の scratch。表示行 → 元行番号のマップ `S.row_to_line` で `<CR>` ジャンプを実現。
