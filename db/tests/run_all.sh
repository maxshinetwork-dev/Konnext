#!/bin/bash
# KONNEXT 契约回归测试 · 一键跑全套
# 用法：./run_all.sh <ddl文件路径>
#
# ★2026-08-04 教训：以前这个脚本只数 "ERROR:" 的条数，把【环境错误】也当成【门禁拦截】。
#   结果 v0.35 的 153 次里混着一串假拦截：集中采购到货因为一个真 bug 被拒
#   （dept_handoff 没标 scope）→ 库存永远是 0 → 后面的出库、退库跟着连环报错，
#   每一条都被记成"拦截成功"。测试全绿，实际上好几个文件什么都没测到。
#   现在按类型分开数，并把【可疑的其他错误】原样打出来 —— 数字不许再骗人。
DDL=${1:-../contract_v0_38.sql}
PSQL="psql -h /tmp -p 5433"
PASS=0; GATE=0; CONS=0; OTHER=0
OTHER_LINES=""
for f in $(ls *.sql | sort); do
  DB="reg_$(echo $f | cut -d_ -f1)"
  $PSQL -c "DROP DATABASE IF EXISTS $DB;" -c "CREATE DATABASE $DB;" >/dev/null 2>&1
  $PSQL -d $DB -v ON_ERROR_STOP=1 -f "$DDL" >/dev/null 2>&1 || { echo "❌ $f 建库失败"; continue; }
  OUT=$($PSQL -d $DB -f "$f" 2>&1 | sed 's/.*ERROR:/ERROR:/')
  N=$(echo "$OUT" | grep -c "ERROR:")
  # 业务门禁：契约里 RAISE EXCEPTION 出来的【中文原句】（门禁提示一律是完整中文句）
  # 三类分开数（按 PostgreSQL 自己的英文报错模式识别，剩下的就是契约 RAISE 出来的中文门禁）
  CONS_RE="violates (check|unique|not-null|foreign key|row-level)|duplicate key|null value in column|permission denied"
  BAD_RE="does not exist|syntax error|invalid input|cannot be cast|is not unique|no such|could not|out of range|too long for"
  C=$(echo "$OUT" | grep "ERROR:" | grep -cE "$CONS_RE")
  O=$(echo "$OUT" | grep "ERROR:" | grep -vE "$CONS_RE" | grep -cE "$BAD_RE")
  G=$((N-C-O))
  echo "  $f → 拦截 $N 次（门禁 $G · 约束 $C$( [ $O -gt 0 ] && echo " · ★其他 $O" ))"
  if [ $O -gt 0 ]; then
    OTHER_LINES="$OTHER_LINES
  ── $f ──
$(echo "$OUT" | grep "ERROR:" | grep -vE "$CONS_RE" | grep -E "$BAD_RE" | sed 's/^/    /')"
  fi
  PASS=$((PASS+N)); GATE=$((GATE+G)); CONS=$((CONS+C)); OTHER=$((OTHER+O))
done
echo "────────────────"
echo "  合计拦截 $PASS 次　＝　门禁（中文原句）$GATE ＋ 约束/权限 $CONS ＋ ★其他 $OTHER"
if [ $OTHER -gt 0 ]; then
  echo ""
  echo "★★★ 有 $OTHER 条不是门禁也不是约束的错误 —— 这些多半是【环境错误/真 bug】，"
  echo "     它们混在拦截数里会让测试看起来是绿的。逐条看清楚再报数字：$OTHER_LINES"
fi
