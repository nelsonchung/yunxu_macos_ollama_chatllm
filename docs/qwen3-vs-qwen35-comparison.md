# `qwen3` 與 `qwen3.5` 比較整理

## 文件目的

整理 Ollama Library 上 `qwen3` 與 `qwen3.5` 兩個系列的主要差異，作為本專案選模型時的快速參考。

這份整理是根據 2026-03-28 查閱以下頁面所得：

- <https://ollama.com/library/qwen3>
- <https://ollama.com/library/qwen3.5>

由於 Ollama Library 頁面內容會持續更新，未來型號、大小、context window、tag 與描述都有可能改變。

## 先看結論

如果只用一句話總結：

- `qwen3` 比較像成熟的純文字推理 / agent / 聊天模型系列
- `qwen3.5` 則是更新一代、能力範圍更大的多模態系列

若是以本專案目前的使用情境來看：

- 只做本地純文字聊天：`qwen3` 仍然很合理
- 想要圖片理解、統一長上下文、更新世代能力：優先考慮 `qwen3.5`

## 核心差異總表

| 面向 | `qwen3` | `qwen3.5` |
| --- | --- | --- |
| 模型定位 | 純文字 LLM 系列 | 多模態系列 |
| 輸入型態 | `Text` | `Text, Image` |
| 頁面標籤 | `tools`, `thinking` | `vision`, `tools`, `thinking`, `cloud` |
| 頁面更新狀態 | 可見型號中有些是 5 個月前 / 10 個月前 | 頁面顯示 3 週前更新 |
| 模型數量 | 58 models | 30 models |
| `latest` 對應 | `qwen3:8b` | `qwen3.5:9b` |
| `latest` 大小 | 5.2GB | 6.6GB |
| 常見 context window | `40K` 為主，部分較新 tag 到 `256K` | 幾乎全面 `256K` |
| 可見最大本地型號 | `235b` | `122b` |
| cloud 變體 | 頁面上未強調 | 頁面明顯帶有 `cloud` 標籤與 cloud 型號 |
| 語言能力描述 | 支援 100+ languages and dialects | 支援 201 languages and dialects |

## 文字版解讀

### 1. `qwen3` 更偏向傳統文字模型家族

Ollama 的 `qwen3` 頁面把它描述為一個完整的 dense + MoE 模型家族，並強調：

- reasoning 能力
- 多輪對話能力
- agent / tools 能力
- 多語言能力

頁面描述裡也明確提到：

- `Qwen3-235B-A22B` 是旗艦模型
- `Qwen3-30B-A3B` 是小型 MoE 模型
- `Qwen3-4B` 被描述為在小模型中表現很強

如果你的需求是：

- 本地文字聊天
- 寫作、問答、整理
- 純文字工具調用

那 `qwen3` 系列仍然很有價值。

### 2. `qwen3.5` 更像新版多模態平台

`qwen3.5` 頁面最明顯的差異有三個：

- 支援 `Text, Image`
- 頁面帶有 `vision`
- 頁面帶有 `cloud`

這代表 `qwen3.5` 不只是 `qwen3` 的小改版，而是更明顯往以下方向擴展：

- 視覺理解
- 更一致的長 context
- 本地與 cloud 混合型號

如果你要做的不是單純聊天，而是：

- 看圖片回答問題
- 視覺 + 文字混合任務
- 很長上下文處理

那 `qwen3.5` 會更值得優先評估。

## 對本專案最有感的差異

### 1. `qwen3:4b` 與 `qwen3.5:4b`

這個比較最接近目前專案的實際使用情境。

| 型號 | 大小 | Context | 輸入 |
| --- | --- | --- | --- |
| `qwen3:4b` | 2.5GB | 256K | Text |
| `qwen3.5:4b` | 3.4GB | 256K | Text, Image |

可直接解讀為：

- `qwen3.5:4b` 比 `qwen3:4b` 更大
- `qwen3.5:4b` 額外提供多模態能力
- 代價是資源需求更高

### 2. 如果是 8GB RAM / Apple Silicon，本地體感差異可能很明顯

雖然 Ollama Library 顯示的大小不是完整等於實際推論時的總記憶體壓力，但仍然有很高參考價值。

在本專案這種本地 macOS chat app 場景中：

- `qwen3:4b` 已經能跑，而且體感上相對可接受
- `qwen3.5:4b` 因為模型更大，推論時大概率更容易讓系統卡頓

這是根據頁面模型大小與本機推論經驗做的推論，不是頁面直接明講的結論。

## context window 的差異怎麼看

頁面上可以看到：

- `qwen3` 有一部分型號還是 `40K`
- 但 `qwen3:4b`、`qwen3:30b`、`qwen3:235b` 等較新 tag 已到 `256K`
- `qwen3.5` 頁面上可見型號幾乎全面 `256K`

這表示：

- `qwen3` 系列的 context window 比較不一致
- `qwen3.5` 看起來更像全面往長上下文統一

若你的產品非常依賴長上下文，`qwen3.5` 的頁面資訊會更讓人放心。

## 哪個比較適合本專案

### 適合維持 `qwen3`

如果你的優先順序是：

- 本地純文字聊天
- 資源占用盡量小
- 先把推理、thinking trace、聊天體驗做好

那目前繼續用 `qwen3` 是合理的。

### 適合試 `qwen3.5`

如果你的優先順序是：

- 想升級到更新世代
- 想做圖片理解
- 想把長上下文當成較穩定的預設能力

那值得測 `qwen3.5`，尤其是：

- `qwen3.5:4b`
- 或 `qwen3.5:9b`（若機器資源允許）

## 我的建議

以這個 repo 目前的方向來看，建議分成兩條路：

### 路線 A：維持 `qwen3:4b` 作為預設

適合：

- 本地文字 chat 為主
- 想保持較穩的資源需求
- 先把 UX、thinking trace、context 管理做好

### 路線 B：增加 `qwen3.5:4b` 作為可選模型

適合：

- 想比較新舊世代體感差異
- 想準備未來做 vision / multimodal 功能
- 想實測在你的機器上是否能接受

如果只選一個作為本 repo 的「穩定預設模型」，我目前仍會偏向：

- `qwen3:4b`

如果是「下一個值得加入的候選模型」，我會選：

- `qwen3.5:4b`

## 參考來源

- Ollama Library: `qwen3`
  - <https://ollama.com/library/qwen3>
- Ollama Library: `qwen3.5`
  - <https://ollama.com/library/qwen3.5>
