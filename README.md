# mdquery.nvim

Markdown の箇条書きに埋め込まれたメタデータ (`#tag` `@key(value)` `key:value` チェックボックス) を抽出し、独自クエリ言語でフィルタリングする Neovim プラグインです。

姉妹プロジェクト `../mdquery-web/` (Next.js) と `../mdquery-vscode/` (VS Code 拡張) の Neovim 版。**外部依存ゼロ・Pure Lua** で実装しています。

## 特徴 (MVP)

- **インクリメンタル更新**: クエリを打つたびに結果がリアルタイム更新 (debounce 付き)
- **縦分割の結果リスト**: 元の Markdown バッファはそのまま、右側に絞り込み結果を表示
- **行ジャンプ**: 結果行で `<CR>` を押すと元バッファの該当行へ移動

## インストール

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  dir = "~/mdquery-nvim",  -- or a git URL
  config = function()
    require("mdquery").setup({})
  end,
}
```

プラグインマネージャを使わない場合は `runtimepath` に追加:

```lua
vim.opt.runtimepath:append("~/mdquery-nvim")
require("mdquery").setup({})
```

## 使い方

1. Markdown ファイルを開く
2. `:MdQuery` を実行 → 入力フロートが開く
3. クエリを入力 (打つたびに結果が更新される)
4. `<Enter>` で確定 → フォーカスが結果リストへ移動
5. 結果行で `<CR>` → 元バッファの該当行へジャンプ

コマンド引数で初期クエリを渡すこともできます:

```
:MdQuery #backend @priority(high)
```

## クエリ構文 (MVP)

スペース区切りの **AND** のみ。各トークン:

| 構文 | 例 | 説明 |
|---|---|---|
| `#tag` | `#backend` | タグ検索 |
| `@key(value)` | `@priority(high)` | メタデータ完全一致 |
| `key:value` | `cost:5000` | メタデータ部分一致 (大小無視) |
| `checked:true` / `checked:false` | | チェックボックス状態 |
| ベアワード | `レビュー` | テキスト部分一致 |

> OR / 否定 `!` / 比較 `>` `<` / 相対日付 / 見出しツリー / HTML コメントメタは Web・VS Code 版にはありますが、本プラグインでは未実装 (今後のフェーズ)。

## キーマップ

### 結果バッファ

| キー | 動作 |
|---|---|
| `<CR>` | カーソル行を元バッファでジャンプ |
| `i` | クエリ入力フロートを (再) 表示 |
| `q` | 結果ウィンドウを閉じる |

### 入力フロート

| キー | 動作 |
|---|---|
| `<Enter>` | クエリ確定、結果へフォーカス移動 |
| `<Esc>` | 入力フロートを閉じる (結果は維持) |

## 設定

```lua
require("mdquery").setup({
  debounce_ms = 200,   -- インクリメンタル更新のデバウンス時間 (ms)
  result_width = 60,   -- 結果分割ウィンドウの幅 (桁)
})
```

## ファイル構成

```
mdquery-nvim/
├── lua/mdquery/
│   ├── init.lua      -- setup(), :MdQuery エントリ
│   ├── parser.lua    -- バッファ → item[] (メタデータ抽出)
│   ├── filter.lua    -- query 文字列 → item[] フィルタ (AND のみ)
│   ├── ui.lua        -- 入力フロート + 結果分割 + ジャンプ
│   └── config.lua    -- 設定
├── plugin/mdquery.lua  -- :MdQuery コマンド登録
├── README.md
└── dear_llm.md
```
