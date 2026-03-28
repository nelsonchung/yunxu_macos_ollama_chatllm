# SwiftUI Ollama Chat App 規劃文件

## 目標

建立一個使用 Swift 撰寫的原生 macOS chat 介面，串接本機 Ollama 服務，並以 `qwen3:4b` 作為第一版預設模型。

這份規劃以以下條件為前提：

- 裝置：MacBook Air M2
- 記憶體：8GB
- 模型：`qwen3:4b`
- Ollama 服務：已可透過 `http://127.0.0.1:11434/api/tags` 確認啟動

## 產品定位

第一版建議先做成「輕量、穩定、可離線使用」的 macOS 原生聊天工具，而不是一次做成全功能 AI 工作台。

MVP 目標如下：

- 可以輸入問題並送出
- 可以接收模型回覆
- 支援串流顯示回覆內容
- 支援多個聊天會話
- 支援本地保存聊天紀錄
- 支援基本參數設定
- 顯示 Ollama 連線狀態與目前模型

## 技術選型建議

建議採用以下技術組合：

- UI：`SwiftUI`
- 架構：`MVVM`
- 網路層：`URLSession` + `async/await`
- 本地資料：第一版用 `JSON` 或 `FileManager`，第二版再評估 `SwiftData`
- 平台：`macOS app`

選擇理由：

- `SwiftUI` 適合快速建立 macOS 原生介面
- `MVVM` 對聊天畫面、輸入狀態、串流狀態管理比較清楚
- Ollama 提供本機 HTTP API，直接用 `URLSession` 即可，不需要額外引入重量級套件
- 第一版先用簡單的本地檔案儲存，能降低開發與除錯成本

## 建議架構

### 1. Model 層

建議至少建立以下資料模型：

#### `ChatMessage`

用途：

- 表示單一聊天訊息

建議欄位：

- `id`
- `role`
- `content`
- `createdAt`
- `status`

其中 `role` 可先定義為：

- `system`
- `user`
- `assistant`

#### `ChatConversation`

用途：

- 表示一組聊天會話

建議欄位：

- `id`
- `title`
- `messages`
- `createdAt`
- `updatedAt`
- `modelName`

#### `AppSettings`

用途：

- 保存模型與 API 設定

建議欄位：

- `baseURL`
- `selectedModel`
- `systemPrompt`
- `temperature`
- `numCtx`
- `streamEnabled`

### 2. Service 層

建議建立一個專責的 `OllamaClient`。

它負責：

- 檢查服務是否在線
- 取得模型清單
- 發送聊天請求
- 處理串流回應
- 轉換錯誤訊息

建議拆出的方法：

- `fetchTags()`
- `chat(messages:model:options:)`
- `streamChat(messages:model:options:)`
- `healthCheck()`

### 3. ViewModel 層

建議至少拆成以下幾個 ViewModel：

#### `ChatViewModel`

負責：

- 管理目前會話
- 管理訊息列表
- 送出訊息
- 更新串流中的 assistant 訊息
- 停止生成
- 顯示錯誤狀態

#### `ConversationListViewModel`

負責：

- 載入會話列表
- 建立新會話
- 切換會話
- 刪除會話
- 更新會話標題

#### `SettingsViewModel`

負責：

- 載入與保存設定
- 切換模型
- 調整生成參數

### 4. View 層

建議第一版畫面採三區結構：

#### 左側欄

- 會話列表
- 新增會話按鈕
- 刪除會話功能

#### 主聊天區

- 訊息列表
- user / assistant 氣泡
- loading 或 streaming 狀態
- 錯誤提示

#### 底部輸入區

- 多行文字輸入框
- `Send` 按鈕
- `Stop` 按鈕
- 顯示目前模型名稱

若要加設定，可先用：

- toolbar sheet
- settings 視窗
- sidebar 底部區塊

## Ollama API 串接規劃

第一版建議直接使用 Ollama 本機 API：

- 模型列表：`GET /api/tags`
- 對話：`POST /api/chat`

建議把 base URL 預設為：

```text
http://127.0.0.1:11434
```

聊天請求建議送出的資料結構概念如下：

```json
{
  "model": "qwen3:4b",
  "messages": [
    { "role": "system", "content": "You are a helpful assistant." },
    { "role": "user", "content": "你好" }
  ],
  "stream": true,
  "options": {
    "temperature": 0.7,
    "num_ctx": 2048
  }
}
```

## 串流設計建議

聊天體驗的關鍵是串流更新，因此第一版就應該把串流列為必要功能。

建議行為：

- 使用者送出訊息後，先立即把 user 訊息加入畫面
- 同時建立一筆空的 assistant 訊息
- 每收到一段串流內容，就附加到 assistant 訊息尾端
- 完成後把 assistant 訊息標記為 finished
- 若中途中止，標記為 cancelled
- 若出錯，保留已生成內容並附加錯誤狀態

這樣可以避免每次都重建整個訊息陣列，UI 更新也會更穩定。

## 針對 M2 / 8GB 的性能建議

你的硬體條件適合先專注在 4B 級別模型，第一版不要把 app 設計得太重。

建議如下：

- 預設模型使用 `qwen3:4b`
- 預設 `num_ctx` 從 `2048` 開始
- 若回覆品質不夠，再測試 `4096`
- 避免一次保留過長的對話上下文
- 超長會話可先做簡單裁切，而不是完整保留全部訊息
- 先不要同時跑多模型切換與背景預載
- UI 避免過多動畫與複雜 markdown 渲染

## 聊天紀錄儲存策略

第一版建議先採用簡單可靠的本地儲存方式。

### MVP 做法

- 每個 conversation 存一個 JSON 檔
- 額外維護一個 conversation index 檔案
- 存放位置可用 app sandbox 內的 Application Support 目錄

優點：

- 好除錯
- 結構清楚
- 容易備份
- 未來可平滑遷移到 `SwiftData`

### 第二版再考慮

- 使用 `SwiftData`
- 加入全文搜尋
- 加入釘選會話
- 加入標籤分類

## 錯誤處理規劃

第一版至少要處理以下錯誤情境：

- Ollama 服務未啟動
- 指定模型不存在
- 請求逾時
- 使用者手動停止生成
- 回傳資料格式不符預期
- 本地儲存失敗

建議錯誤訊息對使用者友善化，例如：

- `無法連線到本機 Ollama 服務，請確認 Ollama 是否已啟動`
- `找不到模型 qwen3:4b，請先在 Ollama 中下載或確認模型名稱`

## UI/UX 建議

第一版重點是順手與穩定，不需要過度設計。

建議優先支援：

- `Enter` 或 `Command + Enter` 送出
- `Shift + Enter` 換行
- 顯示正在生成中
- 支援停止生成
- 可複製訊息內容
- 顯示錯誤提示
- 啟動時自動檢查 Ollama 狀態

可延後功能：

- Markdown 高亮顯示
- code block copy button
- 匯出聊天紀錄
- 自訂主題
- 語音輸入

## 建議目錄結構

如果要從零建立專案，可先朝以下結構整理：

```text
yunxu_macos_ollama_chatllm/
├── docs/
│   └── swiftui-ollama-chat-plan.md
├── App/
│   ├── Models/
│   │   ├── ChatMessage.swift
│   │   ├── ChatConversation.swift
│   │   └── AppSettings.swift
│   ├── Services/
│   │   └── OllamaClient.swift
│   ├── ViewModels/
│   │   ├── ChatViewModel.swift
│   │   ├── ConversationListViewModel.swift
│   │   └── SettingsViewModel.swift
│   ├── Views/
│   │   ├── Sidebar/
│   │   ├── Chat/
│   │   └── Settings/
│   ├── Storage/
│   │   └── ConversationStore.swift
│   └── Utilities/
│       └── Constants.swift
└── README.md
```

## 開發階段建議

建議分四個階段進行。

### Phase 1：打通 Ollama API

目標：

- 建立最小可用 `OllamaClient`
- 成功呼叫 `GET /api/tags`
- 成功呼叫 `POST /api/chat`
- 測通串流更新

完成標準：

- 可以在測試頁面看到模型列表
- 可以送出訊息並取得回覆

### Phase 2：完成單會話聊天畫面

目標：

- 完成基本 chat UI
- 支援輸入、送出、停止
- 支援串流顯示

完成標準：

- 已可當作單一聊天工具使用

### Phase 3：加入多會話與本地儲存

目標：

- 新增/切換/刪除會話
- 保存聊天紀錄
- 重新開啟 app 後可恢復歷史會話

完成標準：

- 已可當作日常本地 chat app 使用

### Phase 4：補上設定與體驗優化

目標：

- 設定模型
- 設定 system prompt
- 設定 temperature / num_ctx
- 補齊錯誤處理與快捷鍵

完成標準：

- 成為可持續迭代的 MVP 基底

## 第一版建議先不要做的項目

以下功能容易讓專案範圍膨脹，建議延後：

- RAG
- 向量資料庫
- 多模型並行比較
- tool calling
- agent workflow
- 雲端同步
- 語音功能
- 複雜的 plugin 架構

## 建議的 MVP 範圍

若要控制開發節奏，第一版只要完成下面這些就很夠用了：

- 原生 macOS SwiftUI app
- 串本機 Ollama
- 使用 `qwen3:4b`
- 支援串流回覆
- 支援聊天紀錄保存
- 支援模型與參數設定
- 支援基本錯誤提示

## 下一步建議

文件完成後，下一步最適合直接進入程式骨架建立。

建議順序如下：

1. 建立 Xcode macOS App 專案
2. 先實作 `OllamaClient`
3. 做出最小聊天畫面
4. 接上串流回覆
5. 再加入本地儲存

如果要接著實作，我建議下一步直接建立一個可執行的 SwiftUI MVP 骨架，優先把 `OllamaClient`、`ChatViewModel` 和基本聊天畫面做出來。
