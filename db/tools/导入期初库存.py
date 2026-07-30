#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
KONNEXT 期初库存导入工具
=========================

用途：系统上线时，把仓库现有存货一次性录进系统。

用法：
    1) 打开「期初库存_填写模板.csv」，把仓库盘点结果填进去
    2) 运行：  python3 导入期初库存.py 期初库存_填写模板.csv
    3) 先看「试算」结果，确认无误后加 --confirm 真正写入：
       python3 导入期初库存.py 期初库存_填写模板.csv --confirm

安全设计：
    · 默认只试算，不写库。必须加 --confirm 才真正导入
    · 整批要么全成功、要么全不写（一个事务）——不会导入一半
    · 一个物料只能做一次期初（数据库层硬拦），做两遍库存会凭空翻倍
    · 物料编号不存在会报错，不会静默跳过
"""

import csv
import sys
import os

try:
    import psycopg2
except ImportError:
    sys.exit("缺少 psycopg2，请先安装：pip install psycopg2-binary")

DSN = os.environ.get("KONNEXT_DSN", "host=/tmp port=5433 dbname=konnext user=postgres")


def read_rows(path):
    rows, errors = [], []
    with open(path, encoding="utf-8-sig", newline="") as f:
        for i, r in enumerate(csv.DictReader(f), start=2):   # 第 1 行是表头
            code = (r.get("物料编号") or "").strip()
            if not code or code.startswith("#"):
                continue
            qty_raw = (r.get("盘点数量") or "").strip()
            cost_raw = (r.get("单位成本AUD") or "").strip()
            note = (r.get("备注") or "").strip() or None
            try:
                qty = float(qty_raw)
            except ValueError:
                errors.append(f"第 {i} 行：盘点数量「{qty_raw}」不是数字")
                continue
            if qty < 0:
                errors.append(f"第 {i} 行：盘点数量不能为负（{qty}）")
                continue
            try:
                cost = float(cost_raw) if cost_raw else None
            except ValueError:
                errors.append(f"第 {i} 行：单位成本「{cost_raw}」不是数字")
                continue
            rows.append((i, code, qty, cost, note))

    dup = {}
    for i, code, *_ in rows:
        dup.setdefault(code, []).append(i)
    for code, lines in dup.items():
        if len(lines) > 1:
            errors.append(f"物料 {code} 在表里出现了 {len(lines)} 次（第 {lines} 行）——请合并成一行")
    return rows, errors


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    path = sys.argv[1]
    confirm = "--confirm" in sys.argv

    rows, errors = read_rows(path)
    if errors:
        print("表格有问题，先改好再导入：\n")
        for e in errors:
            print("  ✗", e)
        sys.exit(1)
    if not rows:
        sys.exit("表里没有可导入的数据。")

    conn = psycopg2.connect(DSN)
    conn.autocommit = False
    cur = conn.cursor()
    cur.execute("SET app.actor = %s", (os.environ.get("KONNEXT_ACTOR", "期初导入"),))

    ok, failed = [], []
    for lineno, code, qty, cost, note in rows:
        try:
            cur.execute("SAVEPOINT sp")
            cur.execute("SELECT fn_opening_stock(%s, %s, %s, %s)", (code, qty, cost, note))
            ok.append((code, qty, cur.fetchone()[0]))
            cur.execute("RELEASE SAVEPOINT sp")
        except Exception as e:
            cur.execute("ROLLBACK TO SAVEPOINT sp")
            msg = str(e).strip().splitlines()[0]
            failed.append((lineno, code, msg))

    print(f"\n共读到 {len(rows)} 行：成功 {len(ok)}，失败 {len(failed)}\n")
    for code, qty, msg in ok[:200]:
        print(f"  ✓ {msg}")
    if failed:
        print()
        for lineno, code, msg in failed:
            print(f"  ✗ 第 {lineno} 行 {code}：{msg}")

    if failed:
        conn.rollback()
        print("\n有失败行，整批已回滚，一条都没写入。请改好表格后重跑。")
        sys.exit(1)

    if confirm:
        conn.commit()
        print("\n✅ 已提交。可用下面这句核对结果：")
        print("   SELECT code, internal_name, opening_qty, current_on_hand")
        print("     FROM v_opening_status WHERE opening_done ORDER BY code;")
    else:
        conn.rollback()
        print("\n⚠️  这是试算，尚未写入数据库。")
        print("    确认无误后加 --confirm 重跑：")
        print(f"    python3 {os.path.basename(sys.argv[0])} {path} --confirm")

    cur.close()
    conn.close()


if __name__ == "__main__":
    main()
