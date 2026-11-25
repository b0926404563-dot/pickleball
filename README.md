# 今天誰贏球 · 俱樂部版

匹克球／羽球俱樂部：Google 登入、報到、即時排賽、填比分＋對手確認、雙項實力分數（仿 DUPR）。

## 目前的系統

| 項目 | 內容 |
|---|---|
| 網站 | https://b0926404563-dot.github.io/pickleball/ |
| 網頁程式 | 本儲存庫 `index.html`（隱私權政策 `privacy.html`） |
| 資料庫 | Supabase 專案 `todaywho`（region: ap-south-1），結構見 `schema.sql` |
| Google 登入 | Google Cloud 專案 `todaywho`，OAuth 已發布（正式環境） |
| 登入轉址 | Supabase Site URL 與 Redirect URL 都設為上方網站網址 |

`schema.sql` 可以重複執行，但**會清空所有資料**（開頭有 drop table），已經有資料時不要直接重跑；要改資料庫結構請寫增量的 SQL。

---

# 今天誰贏球 · 俱樂部版 上線步驟

全部免費，大約 30 分鐘。**請用電腦操作**，手機不方便複製貼上。

你會用到三個檔案：

- `schema.sql`：資料庫結構，只要貼一次
- `index.html`：網頁本體
- 這份說明

---

## 第一步：建立 Supabase 資料庫（約 5 分鐘）

1. 到 **supabase.com** → 右上 **Start your project** → 用 GitHub 或 Google 登入。
2. **New project**：
   - Name：`todaywho`（隨意）
   - Database Password：按 Generate 產生，存起來（平常用不到）
   - Region：選 **Northeast Asia (Tokyo)** 或 **Southeast Asia (Singapore)**，離台灣近比較快
   - 按 **Create new project**，等 1–2 分鐘。
3. 左邊選單 **SQL Editor** → **New query** → 打開 `schema.sql`，**全部複製貼上** → 按 **Run**。
   看到 `Success. No rows returned` 就完成了。
4. 左邊選單 **Project Settings**（齒輪）→ **API**（或 **API Keys**），記下兩個值：
   - **Project URL**：像 `https://abcdefgh.supabase.co`
   - **anon public** key（新版介面叫 **Publishable key**）：一長串文字

   這個 key 本來就是公開用的，放在網頁裡是安全的。資料由資料庫的權限規則保護，只有俱樂部成員看得到自己俱樂部的資料。

## 第二步：開啟 Google 登入（約 10 分鐘）

1. 在 Supabase 左邊選單 **Authentication** → **Sign In / Providers**（或 **Providers**）→ 點 **Google**。
   畫面上有一個 **Callback URL**（像 `https://abcdefgh.supabase.co/auth/v1/callback`），先複製起來。
2. 另開分頁到 **console.cloud.google.com**，用你的 Google 帳號登入：
   - 上方 **選取專案** → **新增專案** → 名稱 `今天誰贏球` → 建立。
   - 左邊選單 **API 和服務** → **OAuth 同意畫面**（新版叫 **Google Auth Platform**）→ 開始設定：
     - 應用程式名稱：`今天誰贏球`；使用者支援電子郵件：你的 Email
     - 目標對象：**外部**
     - 聯絡資訊：你的 Email → 建立
   - 到 **目標對象** 頁面 → **發布應用程式**（不發布的話，只有你手動加入的測試帳號能登入）。
   - 左邊 **用戶端**（或 **憑證** → **建立憑證** → **OAuth 用戶端 ID**）：
     - 應用程式類型：**網頁應用程式**
     - **已授權的重新導向 URI** → 新增 → 貼上第 1 點複製的 Callback URL
     - 建立後會顯示 **用戶端 ID** 和 **用戶端密鑰**，兩個都複製。
3. 回到 Supabase 的 Google 設定頁 → 打開 **Enable** → 貼上 **Client ID** 和 **Client Secret** → **Save**。

## 第三步：把網頁放上 GitHub Pages（約 10 分鐘）

1. 用記事本（Windows）或文字編輯（Mac）打開 `index.html`，找到最上面這兩行：

   ```
   const SUPABASE_URL = '';
   const SUPABASE_KEY = '';
   ```

   把第一步記下的兩個值貼進引號裡，例如：

   ```
   const SUPABASE_URL = 'https://abcdefgh.supabase.co';
   const SUPABASE_KEY = 'eyJhbGciOi...（很長）';
   ```

   存檔。
2. 到 **github.com** 註冊或登入 → 右上 **＋** → **New repository**：
   - Repository name：`pickleball`
   - 選 **Public** → **Create repository**
3. 在新的 repository 頁面點 **uploading an existing file** → 把改好的 `index.html` 拖進去 → **Commit changes**。
4. **Settings** → 左邊 **Pages** → Source 選 **Deploy from a branch** → Branch 選 **main**、資料夾 **/(root)** → **Save**。
   等 1–2 分鐘，上方會出現網址，像：
   `https://你的帳號.github.io/pickleball/`

## 第四步：告訴 Supabase 網站在哪裡（1 分鐘）

Supabase → **Authentication** → **URL Configuration**：

- **Site URL**：貼上 GitHub Pages 網址（`https://你的帳號.github.io/pickleball/`）
- **Redirect URLs** → **Add URL**：`https://你的帳號.github.io/pickleball/**`
- **Save**

## 第五步：開始使用

1. 用手機打開你的 GitHub Pages 網址 → **用 Google 帳號登入** → 取暱稱，填起始分數（可以不填）。
2. **開一個新俱樂部**，例如「一皮闖天下」。你就是團長。
3. 到 **成員** 頁 → **複製邀請連結** → 貼到 LINE 群組。朋友點連結、用 Google 登入、取暱稱，就會自動加入。
4. 建議把網址 **加入主畫面**：Safari 點分享 →「加入主畫面」；Chrome 點選單 →「新增至主畫面」。之後用起來就像 App。

---

## 常見問題

**朋友點 Google 登入出現「存取權遭拒」或「應用程式未經驗證」**
回到第二步，確認 OAuth 同意畫面已經按 **發布應用程式**。如果出現「Google 尚未驗證這個應用程式」，點 **進階** → **前往今天誰贏球** 即可。只用到基本的姓名與 Email，不需要送 Google 審查。

**登入後又跳回登入畫面**
檢查第四步的 Site URL 和 Redirect URLs 是否和 GitHub Pages 網址完全一樣，包含最後的 `/`。

**之後要更新網頁**
到 GitHub repository → 點 `index.html` → 鉛筆圖示編輯，或重新上傳覆蓋。

**一週沒打球，網站打不開**
Supabase 免費方案閒置一週會暫停。到 Supabase 後台按 **Restore project** 就會恢復，資料都還在。每週都有人用就不會發生。

**有朋友沒有 Google 帳號，或只是來玩一次**
在 **開場** 或 **成員** 頁新增「臨時球員」就好。之後他註冊時，暱稱跟臨時球員的名字一樣就會自動接上；或在成員頁點 **這是我** 認領，過去的戰績都會帶過去。

## 權限一覽

| | 團長 | 幹部 | 成員 |
|---|---|---|---|
| 開場、報到、排賽、填比分 | ✓ | ✓ | ✓ |
| 確認對手回報的比分 | ✓ | ✓ | ✓（自己是對手時） |
| 確認任何比分、修改已確認比分 | ✓ | ✓ | |
| 編輯／隱藏球員、刪除活動 | ✓ | ✓ | 只能改臨時球員 |
| 指定幹部 | ✓ | | |

**比分確認規則**：任一方填比分後，要由**對手**按確認才會計入排名和實力分數。如果對手都是沒有帳號的臨時球員，就由其他成員確認；團長或幹部回報這種場次時，會直接確認。
