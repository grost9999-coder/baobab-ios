# 官方保險資料來源爬取試跑紀錄（2026-11-03）

## 範圍與安全界線

本次依「保發中心商品索引 + 保險公司官方網站 + 歷史條款來源」三路做小型只讀試跑。爬蟲先要求 robots.txt 為可解析的純文字且允許目標頁，最低間隔 3 秒；僅抓 HTML 頁面標題、meta 與官方頁面中的連結。**不提交表單、不輸入/繞過 CAPTCHA、不登入、不跟隨跨網域 redirect、不下載 PDF、不複製條款全文，也不自動寫入產品目錄。**

這是 2 家保險公司官網的技術試點，不是對全部保險公司的爬取，也沒有產生商品資料庫。

## 試跑結果

| 資料路線/來源 | 結果 | 可用資訊與限制 |
|---|---|---|
| 保發中心商品查詢：[Query.aspx](https://insprod.tii.org.tw/Query.aspx) | **跳過** | 商品查詢網域的 robots.txt 回應 HTTP 404，因此依 fail-closed 原則不抓查詢頁、不提交查詢，也不嘗試其他端點。頁面本身有圖形驗證碼及分頁。 |
| 台灣人壽官方商品資訊：[商品頁](https://www.taiwanlife.com/AboutUs-public-info-info-insurance) | **公開頁讀取成功** | robots.txt 可解析且允許該頁；頁面標題為「保險商品」。只見大量一般導覽連結，沒有直接條款 PDF 連結，未得到可直接匯入的商品列。 |
| 臺灣產物官方商品條款：[商品頁](https://www.tfmi.com.tw/investors-Product-Terms) | **公開頁讀取成功，但內容不足** | robots.txt 可解析且未禁止該頁；目前返回的 HTML 以「公開依據」等頁面為主，頁面可見連結數多，未發現可直接匯入的商品資料。只辨識到一個 PDF 連結，其名稱指向氣候財務揭露，並非保險商品條款。 |
| 第一產物官方歷史候選條款頁：[汽車條款專區](https://www.firstins.com.tw/insurance/mortorclause) | **跳過** | robots.txt 回傳的內容不是可解析的純文字（疑似攔截/異常頁），頁面也曾回應「網站存取異常」。爬蟲未繼續抓取。搜尋到的公開頁面清單雖列有多個條款 PDF，但不能因此推論其 robots 規則允許自動擷取。 |
| 2004 年以前歷史商品 | **未取得** | 本試跑沒有找到可安全自動使用的官方舊檔案庫。保發中心說明其商品資料庫自 2004 年底開始建置；更早文件仍需另外找官方檔案或由公司/承受公司提供。 |

## 驗證

5 項離線安全測試全數通過：robots.txt 不可讀時停止、HTML 攔截頁不當作 robots.txt、偵測 CAPTCHA 時停止、偵測存取異常時停止，以及只列出 PDF 連結而不下載文件。

## 結論

這次試跑**沒有新增商品、條款或理賠資料**，App 商品目錄仍為 0 筆。它證明可建立一個遵守 robots 規則的來源探索框架，但不能靠通用爬蟲自動獲得全市場完整商品庫。台灣人壽與臺灣產物的頁面要繼續擷取，需先做各站專用的頁面/文件結構解析；任何需 CAPTCHA、存取異常或權利不明的來源都維持停止狀態。若要商用展示條款全文，仍需先確認著作權/再利用權；未獲授權前只適合保留來源連結及人工核對狀態。

## 重跑方式

```sh
python3 scripts/crawl_public_catalog_sources.py \
  --config Resources/crawl_sources.json \
  --output data/crawl_discovery.json
python3 -m unittest discover -s tests -v
```

輸出 `crawl_discovery.json` 是人工審核用的候選來源 metadata，不是商品資料庫，也不應直接供理賠試算使用。
