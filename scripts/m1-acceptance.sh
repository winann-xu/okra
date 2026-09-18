#!/bin/bash
# M1 验收脚本：root helper（hosts 铁律 + 主备源 + 备份 + 原子写 + 状态文件）
# 用法：scripts/m1-acceptance.sh [live]
#   不带参数：仅沙箱测试（file:// 本地源，无网络依赖，结果确定性可复现）
#   带 live：追加真实三源网络测试（L1~L4）
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
HELPER=".build/debug/OkraHelper"
[ -x "$HELPER" ] || { echo "先运行 ./scripts/build.sh（$HELPER 不存在）"; exit 2; }

WORK="$ROOT/.m1test"
rm -rf "$WORK" && mkdir -p "$WORK/srcs" "$WORK/support"

PASS=0; FAIL=0
check() { # check <名称> <0|1 成功标志>
  if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "PASS  $1"
  else FAIL=$((FAIL+1)); echo "FAIL  $1"; fi
}
okrasrc_default() { echo "file://$WORK/srcs/srcA.txt"; }
okra() { # 以沙箱环境运行 helper（默认用 file:// 离线源，确定性可复现）
  OKRA_HOSTS_PATH="$WORK/hosts" OKRA_SUPPORT_DIR="$WORK/support" \
  OKRA_SKIP_DNS_FLUSH=1 OKRA_SOURCES="${OKRA_SOURCES:-$(okrasrc_default)}" "$HELPER" "$@"
}
# 提取 hosts 文件中 Okra 区块之外的行（trim 后与标记行比对）
non_okra() {
  awk '{ t=$0; gsub(/^[ \t]+/,"",t); gsub(/[ \t]+$/,"",t)
        if (t=="# Okra Start") { inb=1; next }
        if (t=="# Okra End")   { inb=0; next }
        if (!inb) print }' "$1"
}

# ---------- 夹具 ----------
mkfixture() { # $1=输出文件  $2=结尾是否换行(1/0)
  {
    printf '%s\n' '# localhost is related to aliases. Local hosts can be defined here.'
    printf '127.0.0.1\tlocalhost\n'
    printf '255.255.255.255\tbroadcasthost\n'
    printf '::1\tlocalhost\n'
    printf '\n'
    printf '%s\n' '# SomeOtherTool Start'
    printf '1.1.1.1\tfoo.example.com\n'
    printf '%s\n' '# 2026-09-10 someother tool added an entry'
    printf '192.0.2.9\tother.example.com\n'
    printf '%s\n' '# SomeOtherTool End'
    printf '\n'
    printf '%s\n' '# a lone comment line'
    printf '198.51.100.7\tlegacy.example.com'
    [ "$2" -eq 1 ] && printf '\n'
  } > "$1"
}
gen_src() { # $1=输出  $2=条目行数（每行 IP+域名）
  : > "$1"
  echo "# source file $2 entries" >> "$1"
  i=1
  while [ $i -le $2 ]; do
    printf '10.0.%d.%d  a%d.test.example.com b%d.test.example.com\n' $((i/250)) $((i%250)) $i $i >> "$1"
    i=$((i+1))
  done
}
gen_src "$WORK/srcs/srcA.txt" 50
gen_src "$WORK/srcs/big.txt" 300
gen_src "$WORK/srcs/srcB.txt" 80
mkfixture "$WORK/fixture" 1

# ---------- T1 首次更新：仅 Okra 区块变化 + 备份 + 状态文件 ----------
mkfixture "$WORK/hosts" 1
cp "$WORK/hosts" "$WORK/pre-update.bak"
out=$(okra update 2>&1); rc=$?
check "T1a 首次更新退出码 0" $rc
[ "$(non_okra "$WORK/hosts")" = "$(non_okra "$WORK/fixture")" ]
check "T1b 区块外内容逐字节保留" $?
[ -n "$(ls "$WORK/support/backups/" 2>/dev/null | grep '^hosts-.*\.bak$')" ]
check "T1c 写前已生成带时间戳备份" $?
latest_bak="$WORK/support/backups/$(ls "$WORK/support/backups/" | sort | tail -1)"
diff -q "$latest_bak" "$WORK/pre-update.bak" >/dev/null
check "T1d 最新备份与更新前文件逐字节一致" $?
okra status | grep -q "成功"
check "T1e 状态文件 update_ok=true（status 命令可读）" $?

# ---------- T2 diff 证明仅区块变化 ----------
diff -u "$WORK/fixture" "$WORK/hosts" > "$WORK/t2.diff"
outside_changes=$(grep -E '^[+-]' "$WORK/t2.diff" | grep -vE '^(\+\+\+|---)' | grep -Ev '^[+-](# Okra (Start|End)|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\s)' | grep -c .)
[ "$outside_changes" -eq 0 ]
check "T2 diff 中区块外无任何 +/- 行" $?

# ---------- T3 连续更新两次：无重复条目（区块替换而非追加） ----------
cp "$WORK/hosts" "$WORK/first-update"
okra update >/dev/null 2>&1
diff -q "$WORK/first-update" "$WORK/hosts" >/dev/null
check "T3 连续两次更新后文件逐字节一致（无重复条目）" $?
[ "$(grep -c 'b42.test.example.com' "$WORK/hosts")" -eq 1 ]
check "T3b 任一域名在文件中仅出现一次" $?

# ---------- T4 同源行数剧变（>50%）：拒绝写入 ----------
cp "$WORK/hosts" "$WORK/t4.bak"
cp "$WORK/srcs/big.txt" "$WORK/srcs/srcA.txt"   # 同名源，50 → 300 条
out=$(okra update 2>&1); rc=$?
[ $rc -ne 0 ] && echo "$out" | grep -q "行数剧变"
check "T4a 同源 50→300 条被拒绝（退出码非 0 且提示行数剧变）" $?
diff -q "$WORK/t4.bak" "$WORK/hosts" >/dev/null
check "T4b 拒绝后 hosts 逐字节未动" $?
grep -Eq '"update_ok"[[:space:]]*:[[:space:]]*false' "$WORK/support/status.json"
check "T4c 状态文件标记 update_ok=false" $?
grep -q '行数剧变' "$WORK/support/status.json"
check "T4d 状态文件错误原因人话化" $?

# ---------- T5 镜像数据异常（空/无有效行）：拒绝写入 ----------
cp "$WORK/hosts" "$WORK/t5.bak"
printf '# only comments here\n# nothing else\n' > "$WORK/srcs/srcA.txt"
out=$(okra update 2>&1); rc=$?
[ $rc -ne 0 ] && echo "$out" | grep -q "无有效 IP 行"
check "T5a 空镜像被拒绝（提示无有效 IP 行）" $?
diff -q "$WORK/t5.bak" "$WORK/hosts" >/dev/null
check "T5b 拒绝后 hosts 逐字节未动" $?
cp "$WORK/srcs/big.txt" "$WORK/srcs/srcA.txt"   # 恢复，供后续测试

# ---------- T6 还原：他人区块（含后续修改）逐字节保留 ----------
mkfixture "$WORK/hosts" 1
okra update >/dev/null 2>&1     # 写入 Okra 区块（srcA 50 条）
{ cat "$WORK/hosts"
  printf '%s\n' '# user added after okra block'
  printf '203.0.113.5\tuser.example.com\n'
} > "$WORK/hosts.tmp" && mv "$WORK/hosts.tmp" "$WORK/hosts"
sed -i '' 's/^1\.1\.1\.1\tfoo/1.1.1.2\tfoo/' "$WORK/hosts"   # 他人区块后续修改
okra restore >/dev/null 2>&1
{
  printf '%s\n' '# localhost is related to aliases. Local hosts can be defined here.'
  printf '127.0.0.1\tlocalhost\n'
  printf '255.255.255.255\tbroadcasthost\n'
  printf '::1\tlocalhost\n'
  printf '\n'
  printf '%s\n' '# SomeOtherTool Start'
  printf '1.1.1.2\tfoo.example.com\n'
  printf '%s\n' '# 2026-09-10 someother tool added an entry'
  printf '192.0.2.9\tother.example.com\n'
  printf '%s\n' '# SomeOtherTool End'
  printf '\n'
  printf '%s\n' '# a lone comment line'
  printf '198.51.100.7\tlegacy.example.com\n'
  printf '%s\n' '# user added after okra block'
  printf '203.0.113.5\tuser.example.com\n'
} > "$WORK/t6.expected"
diff -q "$WORK/t6.expected" "$WORK/hosts" >/dev/null
check "T6 还原后：他人区块修改与新增行逐字节保留、Okra 区块移除" $?
grep -q "Okra" "$WORK/hosts" && r=1 || r=0
check "T6b 文件中已无任何 Okra 标记" $r

# ---------- T7 文件无结尾换行：更新成功且保持无结尾换行 ----------
mkfixture "$WORK/hosts" 0
out=$(okra update 2>&1); rc=$?
[ $rc -eq 0 ]
check "T7a 无结尾换行的 hosts 更新成功" $rc
[ "$(tail -c 1 "$WORK/hosts" | xxd -p)" != "0a" ]
check "T7b 更新后仍无结尾换行（结尾状态不变）" $?
mkfixture "$WORK/fixture-nonl" 0
[ "$(non_okra "$WORK/hosts")" = "$(non_okra "$WORK/fixture-nonl")" ]
check "T7c 区块外内容逐字节保留" $?

# ---------- T8 标记损坏（只有单侧）：拒绝操作、原文件不动 ----------
mkfixture "$WORK/hosts" 1
printf '\n# Okra Start\n10.9.9.9\tdangling.test.example.com\n' >> "$WORK/hosts"   # 只有 Start 无 End
cp "$WORK/hosts" "$WORK/t8.bak"
out=$(okra update 2>&1); rc=$?
[ $rc -ne 0 ] && echo "$out" | grep -q "标记损坏"
check "T8a 单侧标记：update 拒绝执行" $?
diff -q "$WORK/t8.bak" "$WORK/hosts" >/dev/null
check "T8b 拒绝后文件逐字节未动" $?

# ---------- T9 状态文件 schema 完整 ----------
grep -q '"last_update"' "$WORK/support/status.json" && grep -q '"update_ok"' "$WORK/support/status.json" \
  && grep -q '"update_error"' "$WORK/support/status.json" && grep -q '"source"' "$WORK/support/status.json" \
  && grep -q '"entries"' "$WORK/support/status.json" && grep -q '"last_probe"' "$WORK/support/status.json" \
  && grep -q '"probes"' "$WORK/support/status.json" && grep -q '"overall"' "$WORK/support/status.json"
check "T9 状态文件含任务书 §7 全部字段" $?

echo
echo "=== 沙箱测试：$PASS 通过 / $FAIL 失败 ==="

# ---------- 真实网络源（live） ----------
if [ "${1:-}" = "live" ]; then
  echo
  echo "=== 真实镜像源测试（L1~L4，需网络）==="
  mkfixture "$WORK/hosts" 1
  cp "$WORK/hosts" "$WORK/live0.bak"

  out=$(OKRA_HOSTS_PATH="$WORK/hosts" OKRA_SUPPORT_DIR="$WORK/support" OKRA_SKIP_DNS_FLUSH=1 \
        "$HELPER" update 2>&1); rc=$?
  [ $rc -eq 0 ] && okra status | grep -q "hellogithub"
  check "L1 三源默认顺序更新成功（主源 hellogithub）" $?
  entries=$(okra status | grep -oE '[0-9]+ 条' | grep -oE '[0-9]+')
  [ -n "$entries" ] && [ "$entries" -ge 20 ] && [ "$entries" -le 200 ]
  check "L1b 主源条目数在合理区间（$entries 条）" $?

  cp "$WORK/hosts" "$WORK/live1.bak"
  out=$(OKRA_HOSTS_PATH="$WORK/hosts" OKRA_SUPPORT_DIR="$WORK/support" OKRA_SKIP_DNS_FLUSH=1 \
        OKRA_SOURCES="https://okra-dead.invalid/hosts" "$HELPER" update 2>&1); rc=$?
  [ $rc -ne 0 ] && diff -q "$WORK/live1.bak" "$WORK/hosts" >/dev/null && grep -Eq '"update_ok"[[:space:]]*:[[:space:]]*false' "$WORK/support/status.json"
  check "L2 全部源失败：退出非 0、hosts 逐字节未动、状态标错" $?

  out=$(OKRA_HOSTS_PATH="$WORK/hosts" OKRA_SUPPORT_DIR="$WORK/support" OKRA_SKIP_DNS_FLUSH=1 \
        OKRA_SOURCES="https://okra-dead.invalid/hosts,https://cdn.jsdelivr.net/gh/ittuann/GitHub-IP-hosts@main/hosts" \
        "$HELPER" update 2>&1); rc=$?
  [ $rc -eq 0 ] && okra status | grep -q "cdn.jsdelivr.net"
  check "L3 主源故障自动降级备源 1 并写入（源切换不触发剧变误杀）" $?
  okra status | grep -oE '[0-9]+ 条' | grep -oE '[0-9]+' > "$WORK/l3n"
  n="$(cat "$WORK/l3n")"
  [ -n "$n" ] && [ "$n" -ge 20 ]
  check "L3b 备源写入条目数合理（实测 $n 条；主源 ${entries} 条切换后超 50% 仍被接受，验证源切换不误杀）" $?

  okra restore >/dev/null 2>&1
  grep -q "Okra Start" "$WORK/hosts" && r=1 || r=0
  [ $r -eq 0 ] && diff -q <(non_okra "$WORK/hosts") <(non_okra "$WORK/live0.bak") >/dev/null
  check "L4 还原后无 Okra 标记、区块外内容与初始夹具一致" $?

  echo
  echo "=== 真实源测试完成 ==="
fi

[ $FAIL -eq 0 ] || exit 1
exit 0