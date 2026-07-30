#!/bin/bash
# KONNEXT 契约回归测试 · 一键跑全套
# 用法：./run_all.sh <ddl文件路径>
DDL=${1:-../contract_v0_6.sql}
PSQL="psql -h /tmp -p 5433"
PASS=0
for f in $(ls *.sql | sort); do
  DB="reg_$(echo $f | cut -d_ -f1)"
  $PSQL -c "DROP DATABASE IF EXISTS $DB;" -c "CREATE DATABASE $DB;" >/dev/null 2>&1
  $PSQL -d $DB -v ON_ERROR_STOP=1 -f "$DDL" >/dev/null 2>&1 || { echo "❌ $f 建库失败"; continue; }
  N=$($PSQL -d $DB -f "$f" 2>&1 | grep -c "ERROR:")
  echo "  $f → 拦截 $N 次"
  PASS=$((PASS+N))
done
echo "────────────────"
echo "  合计拦截 $PASS 次"
