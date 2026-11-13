# Baobab iOS — 保單整理原型

SwiftUI iOS 17+ prototype for photographing policy pages, manually confirming policy records, reviewing coverage-record gaps, and estimating a conservative minimum from explicitly verified benefits.

## 功能（五個分頁）

1. **總覽／建立保單：** 手動輸入或拍照辨識（裝置端 Vision OCR）。**保險公司欄位支援簡稱自動比對**：輸入「南山」會列出「南山人壽保險股份有限公司」「南山產物保險股份有限公司」並帶入公司代碼（「臺／台」視為相同，並支援國壽、台壽、新壽、郵局、AIA 等常用簡稱）。**商品名稱欄位支援關鍵字自動完成**（例如「住院」），結果含現售與停售、主約/附約，並可依已選公司縮小範圍。OCR 候選值只能逐項手動採用，不會自動確認。
2. **保單健檢：** 逐張列出住院日額（含日數上限、單次最高累計、條款可投保上下限與超出範圍提示）、一般身故、意外身故、意外住院日額、骨折未住院、手術、門診手術、實支實付；另有全部保單合計（已核對／未核對分開）、保障類別紀錄與資料待補。未記錄只代表「資料未填」，不判定缺口，也不評價保額是否足夠。
3. **商品與條款：** 用簡稱找公司、用關鍵字找商品，可依現售/停售與主約/附約篩選；商品詳頁有條款版本、核驗狀態、給付項目。若商品有 HTTPS 條款網址則直接開啟；沒有時提供**間接連結**（保發中心查詢頁、網頁搜尋），並標明未經本 App 核驗。可匯入附授權記錄的商品目錄 JSON（見下）。
4. **理賠預估：** 可貼上或拍照辨識**醫囑**（例如「右側腎結石，執行雙J導管內視鏡結石取出，住院3天」）。App 在裝置端解析出診斷、側別、手術/處置、住院天數、門診/意外/骨折提示與手術表比對關鍵字，填入可修改的欄位；辨識文字與照片不保存、不上傳。估算只合計**條款已核對、保單有效期間確認、金額明確**的項目：住院日額 × min(住院天數, 日數上限)、意外住院日額、骨折未住院，以及你逐張核對過金額的手術給付。實支實付不以保額代替。結果為「已知最低估算」，不是理賠承諾。
5. **拍照建檔：** 拍攝或選取保單頁面，辨識後進入核對。

保單記錄存放在 App 的 Application Support 資料夾，使用 iOS 完整檔案保護並排除裝置備份。模型刻意不保存保單號碼、被保險人姓名、身分證字號、地址與 OCR 原文。這是原型的儲存設計，不是資安認證。

## Important data limitation

This repository does **not** contain a verified, complete database of all Taiwan insurers' current and discontinued products or their clauses. `Resources/product_catalog.json` contains 61 insurer/company filter entries copied as displayed by the official TII query page, but includes historical, pre-merger and status-unconfirmed entries; it is not a current insurer license roster. It currently contains **0 product records**.

The TII search page supports company/type/product keyword and sales/stop-sale date filters, but presents CAPTCHA and paginated results. We did not find a public bulk export/API or a verified commercial redistribution grant for the TII product documents. The official product database says it began in late 2004 and may omit earlier or newly submitted products. Do not bypass the CAPTCHA, guess private endpoints, or repackage terms without documented rights. Add records only from an authorized, traceable source and verify every clause version.

A separate `Insurance` repository in the same account contains a 3,324-row export spanning only eight life insurers. Those entries have basic names/status/year but no product codes, clause text, clause links, or source lineage. The export is not included as verified production data and must not be used for claim calculations.

## 匯入完整商品目錄

App 的搜尋、自動完成與條款連結都已完成，**資料量取決於 `product_catalog.json`**。取得有授權的資料後有兩種方式：

- 打包進 App：把商品加入 `Resources/product_catalog.json` 的 `products`，先執行 `python3 scripts/validate_product_catalog.py`。
- 不重新編譯：在「商品與條款」頁右上角選單匯入 JSON。App 會拒收沒有 `rightsStatus`（authorized／public_open_license）、HTTPS `rightsEvidenceURL`、`rightsCheckedOn` 的檔案，也會拒收引用未知公司代碼的商品；宣稱 verified 卻缺少條款/來源欄位的商品會降為「待人工核對」。

每筆商品可帶 `role`（主約／附約／未確認）；給付項目 `kind` 可用：住院日額、手術定額、手術表定額、門診手術、實支實付、一般身故、意外身故、意外住院日額、骨折未住院、其他，並可用 `limitMinNTD`／`limitMaxNTD` 記錄條款可投保範圍。

### 索引模式（只收名稱、銷售期間與官網連結）

不收條款全文時，在目錄 `source.rightsStatus` 填 `index_links_only`：每筆商品只帶名稱、`role`、`salesStatus`、`effectiveFrom`/`salesEnd` 與指向公司官網的 HTTPS `sourceURL`，`benefits` 必須為空且不得標 verified。仍須附 `rightsEvidenceURL`（該公司網站使用條款或公開說明頁）與 `rightsCheckedOn`。範本見 [`docs/product-index-template.json`](docs/product-index-template.json)，可用 `python3 scripts/validate_product_catalog.py docs/product-index-template.json` 檢查。資料須逐家人工從官網核對，不得繞過驗證碼或大量擷取保發中心資料庫。

## Safe crawler prototype

The read-only crawler checks robots.txt first and stops on CAPTCHA, access interstitials, non-plain robots responses, or HTTP blocking. It does not submit forms, follow redirects, download clause files, or import candidate links as products. Run it with `python3 scripts/crawl_public_catalog_sources.py`; it is source discovery only, not a full-catalog importer. Nine tests (five crawler safety tests, four catalog validator tests) pass with `python3 -m unittest discover -s tests -v`. The first official-source pilot found that some public pages expose only navigation/JavaScript-loaded content, while TII robots.txt and one insurer site's access response require stopping rather than bypassing. See [`docs/crawler-pilot-2026-11-03.md`](docs/crawler-pilot-2026-11-03.md).

## Build

Open `Baobab.xcodeproj` in Xcode 15 or later and run on iOS 17+. The source uses SwiftUI, PhotosUI, UIKit camera picker, and on-device Vision OCR. This coding environment does not include Xcode or an iOS SDK, so **no Swift code in this repository has been compiled or run here**; the first Xcode build may surface compile errors to fix. The insurer-name matching and medical-order regex logic were cross-checked with a Python port.

## Official references

- Taiwan Insurance Institute product database: https://www.tii.org.tw/tii/insurance/insurance4.html
- TII public product query: https://insprod.tii.org.tw/Query.aspx
- Taiwan Insurance Bureau public-information portal: https://ins-info.ib.gov.tw/
- Product data schema and verification rules: [`docs/product-data-schema.md`](docs/product-data-schema.md)
- Three-track data acquisition plan and unsent request drafts: [`docs/data-acquisition-plan-and-requests.md`](docs/data-acquisition-plan-and-requests.md)
- Catalog format checker: `python3 scripts/validate_product_catalog.py`
- Crawler source settings: `Resources/crawl_sources.json`
