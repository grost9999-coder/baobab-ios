# 商品與條款資料規格

## 核心原則

保單給付必須綁定「保險公司 + 商品代碼/名稱 + 條款版本 + 保單生效日」。商品現售/停售是銷售狀態，不代表既有契約保障消失或變更。每份使用者保單保存其簽發版本，不能只連到最新版條款。

## 商品紀錄必要欄位

- `insurer_id`, `insurer_name`, `line_of_business`（壽險/產險）、`product_code`, `product_name`, `rider_or_base`
- `sales_status`（on_sale/discontinued/unknown）、`sales_start`, `sales_end`, `status_checked_at`
- `clause_version`, `clause_effective_date`, `clause_document_url`, `clause_sha256`
- `source_url`, `source_publisher`, `retrieved_at`, `source_document_date`
- `verification_status`（unreviewed/verified/conflicted/unavailable）、`verified_at`, `review_notes`
- 給付項目：給付類型、觸發條件、金額/公式、限額、等待期、除外責任、手術表/代碼、條款章節及原文頁碼

缺少必要版本、條款文件、來源或核對日期時，資料只能用於搜尋提示，不可用於理賠估算。

## OCR 保單資料

照片辨識欄位只建立 draft。姓名、身分證、地址、保單號、病歷資料不得傳到第三方辨識服務，除非使用者明確同意且有必要的資安、保存期限、刪除及存取控制。此原型使用裝置端 OCR，辨識原文與照片不寫入保單檔案；保單儲存只保留經使用者確認的公司、商品、保障類別、條款來源和給付欄位。保單檔案採 iOS 完整檔案保護並排除裝置備份。

## 「最低可理賠金額」試算規則

目前應稱「已知最低估算」而非保證理賠額。需核對條款版本、條號/頁碼、HTTPS 來源及保單生效期間，才可納入該保單。只納入輸入條件明確且不需額外事實判斷的定額項目。手術給付需依每張保單、每個就醫事件由使用者核對手術表項目與金額。實支實付需收據與限額/除外/重複保險等判斷，不可把保額直接當理賠額。手術表、代碼或適應症未核對時顯示待查，不以手術名稱猜金額。結果列出納入與未納入的項目、依據條款頁碼、版本及來源。

## 來源與範圍

保險事業發展中心說明其商品資料庫自 2004 年底開始建置，資料不一定涵蓋 2004 年以前商品或尚未送交的新商品。因此需要按公司向官方商品查詢入口、公司正式條款檔案及可用歷史檔案逐筆補齊，並將找不到資料的商品標成 unavailable，而非推估補寫。
