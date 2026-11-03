#!/usr/bin/env python3
"""Convert user-supplied insurer product-name lists into Baobab catalog records.

Records are NAME-ONLY search hints: dataQuality=needsReview, no clauses, no benefits,
salesStatus=未確認 unless the source itself states a stop-sale/stop-accept date.
Run:  python3 scripts/import_user_supplied_names.py
"""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "data" / "user_supplied"
CATALOG = ROOT / "Resources" / "product_catalog.json"

SCREENSHOT_NOTE = "來源為使用者提供的官網截圖/文字整理，名稱可能有誤字、截斷或合併條目，需對照保險公司官網核對。"


def clean(s):
    s = s.replace("**", "").strip()
    s = re.sub(r"[。/]+$", "", s)
    s = re.sub(r"等$", "", s)
    return s.strip(" 、,")


def code_from_name(name):
    m = re.search(r"\(([A-Z0-9][A-Z0-9 /]*)\)\s*$", name)
    # 純數字（如 (110)、(2020)）是版本/年份，不是商品代碼
    return m.group(1).strip() if m and re.search(r"[A-Z]", m.group(1)) else None


def rec(company, code, name, doc, note, status="未確認", sales_end=None, product_code=None, extra=""):
    h = hashlib.sha1(f"{code}|{name}".encode("utf-8")).hexdigest()[:10]
    r = {
        "id": f"{code}-{h}",
        "company": company,
        "companyCode": code,
        "name": name,
        "line": "壽險",
        "salesStatus": status,
        "provenance": f"使用者提供名稱清單：{doc}。{note}{extra}僅為搜尋提示；未核對現售狀態、條款版本或給付內容。",
        "dataQuality": "needsReview",
        "benefits": [],
    }
    if product_code:
        r["productCode"] = product_code
    if sales_end:
        r["salesEnd"] = sales_end
    return r


def numbered(path, company, code, doc, note):
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\d{3}\.\s+(.+)$", line.strip())
        if m:
            name = clean(m.group(1))
            out.append(rec(company, code, name, doc, note, product_code=code_from_name(name)))
    return out


def nanshan(path):
    text = path.read_text(encoding="utf-8")
    out = []
    # entries: "NNN. 文宣品號：XXX" followed by indented lines
    blocks = re.split(r"\n(?=\d{3}\. 文宣品號：)", text)
    for b in blocks:
        m = re.match(r"(\d{3})\. 文宣品號：(\S+)\n(.*)", b, re.S)
        if not m:
            continue
        _, mat, body = m.groups()
        body = re.split(r"\n\n【[^\n]*文宣條目】", body)[0]  # 切掉下一個章節標題
        lines = [l.strip() for l in body.splitlines() if l.strip()]
        if mat in ("PA413", "PA443", "PA454", "MP584", "MP589", "MP-04-1130046", "e-DM", "PA400", "PA421"):
            continue  # 專刊/型錄/e-DM，非單一商品
        status, end, note = "未確認", None, ""
        names = []
        for i, l in enumerate(lines):
            if l.startswith("英文簡稱："):
                continue
            if l.startswith("來源狀態："):
                st = l[len("來源狀態："):]
                if "停止銷售" in st or "停止受理" in st:
                    status = "停售"
                    d = re.search(r"(\d+)年(\d+)月(\d+)日", st)
                    if d:
                        y, mo, dd = int(d.group(1)) + 1911, int(d.group(2)), int(d.group(3))
                        end = f"{y:04d}-{mo:02d}-{dd:02d}T00:00:00Z"
                    note = f"來源標示：{st}。"
                continue
            if "文宣條目】" in l or (l.startswith("【") and not names):
                continue  # 章節標題/前置註記，不是商品名稱
            if not names or l.startswith("南山人壽"):
                names.append(l)
            else:
                names[-1] += l  # continuation line
        flat = []
        for n in names:
            flat.extend(re.split(r"/(?=南山人壽)", n))
        for n in flat:
            n = clean(n)
            if n:
                out.append(rec("南山人壽保險股份有限公司", "206", n, f"南山商品簡介暨行銷文宣一覽表（文宣品號 {mat}，製表 2026-10-01）",
                               note, status, end, code_from_name(n)))
    return out


def farglory(path):
    out, seen = [], set()
    for line in path.read_text(encoding="utf-8").splitlines():
        if not re.match(r"^\s*-\s", line):
            continue
        body = re.sub(r"^\s*-\s*", "", line).replace("**", "")
        if "：" in body:
            head, desc = body.split("：", 1)
            if not desc.strip():
                continue
            body = head
        for n in re.split(r"\s+/\s+", body):
            n = clean(n)
            if n and n not in seen:
                seen.add(n)
                extra = "" if n.startswith("遠雄") else "名稱缺公司前綴，疑似截斷。"
                out.append(rec("遠雄人壽保險事業股份有限公司", "216", n, "遠雄人壽保險商品分類總覽", SCREENSHOT_NOTE, extra=extra, product_code=code_from_name(n)))
    return out


def mercuries(path):
    out, seen = [], set()
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw.startswith(" ") or raw.startswith("\t"):
            continue
        line = raw.strip()
        m = re.match(r"^(?:-\s+|\d+\.\s+)(.+)$", line)
        if not m:
            continue
        body = m.group(1).replace("**", "")
        if "如：" in body:
            body = body.split("如：", 1)[1]
        elif "：" in body:
            head, rest = body.split("：", 1)
            if not rest.strip():
                continue
            if "特色" in head or "幣別" in head:
                continue
            body = rest
        for n in body.split("、"):
            n = clean(n)
            if n and n not in seen and len(n) > 3:
                seen.add(n)
                extra = "" if n.startswith("三商美邦") else "名稱為簡稱或缺公司前綴，需核對完整名稱。"
                if "/" in n:
                    extra += "此條目可能合併多個商品，需拆分核對。"
                out.append(rec("三商美邦人壽保險股份有限公司", "211", n, "三商美邦人壽保險商品分類總覽", SCREENSHOT_NOTE, extra=extra, product_code=code_from_name(n)))
    return out


def cathay_kgi(path):
    out, seen = [], set()
    company = None
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("## "):
            if "國泰" in line:
                company = ("國泰人壽保險股份有限公司", "204")
            elif "凱基" in line:
                company = ("凱基人壽保險股份有限公司", "205")
            continue
        m = re.match(r"^\*\s+(.+)$", line)
        if not m or not company:
            continue
        for n in re.split(r"\s+/\s+", m.group(1)):
            series = "系列" in n
            n = clean(n.replace("系列", ""))
            if not n or (company[1], n) in seen:
                continue
            seen.add((company[1], n))
            extra = "官網列為系列名稱，需展開為實際商品名稱。" if series else ""
            if not n.startswith(("國泰", "凱基")):
                extra += "名稱缺公司前綴，需核對完整名稱。"
            out.append(rec(company[0], company[1], n, "國泰人壽與凱基人壽官方網站商品列表截圖整理", SCREENSHOT_NOTE, extra=extra, product_code=code_from_name(n)))
    return out


def main():
    products = []
    products += numbered(SRC / "shinkong.txt", "新光人壽保險股份有限公司", "208", "新光人壽商品名稱彙整（2026-10-04）", "原文件標示：不代表全部商品或已查證的現售清單。")
    products += numbered(SRC / "pruadvisor.txt", "保誠人壽保險股份有限公司", "203", "保誠人壽商品名稱彙整（2026-10-04）", "原文件標示：不代表全部商品或目前銷售狀態。")
    products += nanshan(SRC / "nanshan.txt")
    products += farglory(SRC / "farglory.txt")
    products += mercuries(SRC / "mercuries.txt")
    products += cathay_kgi(SRC / "cathay_kgi.md")

    ids = set()
    uniq = []
    for p in products:
        if p["id"] in ids:
            continue
        ids.add(p["id"])
        uniq.append(p)

    payload = json.loads(CATALOG.read_text(encoding="utf-8"))
    payload["products"] = uniq
    payload["dataStatus"] = "user_supplied_names_only"
    payload["source"]["rightsStatus"] = "user_supplied_names_only"
    payload["source"]["notes"] = (
        "公司索引來自保發中心查詢下拉（原樣記錄）。商品為使用者提供的 7 家壽險公司名稱清單，僅作搜尋提示："
        "未核對現售/停售、條款版本或給付內容，無條款全文，不可用於理賠估算。"
    )
    CATALOG.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    by = {}
    for p in uniq:
        by.setdefault(p["company"], [0, 0])
        by[p["company"]][0] += 1
        by[p["company"]][1] += p["salesStatus"] == "停售"
    for k, (n, s) in by.items():
        print(f"{k}: {n} 筆（來源標示停售 {s}）")
    print(f"合計 {len(uniq)} 筆")


if __name__ == "__main__":
    main()
