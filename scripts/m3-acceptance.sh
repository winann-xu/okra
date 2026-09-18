#!/bin/bash
# M3 验收：一键还原"其余 hosts 内容逐字节保留"沙箱验证（无需 root，OKRA_* 环境变量覆盖路径）。
# 任务书 §9 M3 验收第 2 条 + §7 铁律回归。
# 用法：scripts/m3-acceptance.sh（先跑 scripts/build.sh）
set -u
cd "$(dirname "$0")/.."

HELPER=./.build/debug/OkraHelper
[ -x "$HELPER" ] || { echo "helper 未构建（先跑 scripts/build.sh）"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0
check() { # $1=描述  $2=0/非0
  if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "✅ $1"
  else FAIL=$((FAIL+1)); echo "❌ $1"; fi
}

HOSTS=$WORK/hosts
SRC=$WORK/mirror.txt

# 区块外行提取（跳过 # Okra Start / # Okra End 之间的行，允许标记行含空白）
non_okra() { awk '{
    if ($0 ~ /^[[:space:]]*# Okra Start[[:space:]]*$/) { inblk=1; next }
    if ($0 ~ /^[[:space:]]*# Okra End[[:space:]]*$/) { inblk=0; next }
    if (!inblk) print
  }' "$1"; }

run() { OKRA_HOSTS_PATH="$HOSTS" OKRA_SUPPORT_DIR="$WORK/okra" \
        OKRA_SOURCES="file://$SRC" OKRA_SKIP_DNS_FLUSH=1 \
        "$HELPER" "$@"; }

# --- 夹具 ---
# 他人工具的 hosts 区块（GitHub520 风格）+ 区块外用户自定义行——Okra 绝不允许触碰
cat > "$HOSTS" <<'EOF'
##
# Host Database
#
# localhost is used to configure the loopback interface
# when the system is booting.  Do not change this entry.
##
127.0.0.1	localhost
255.255.255.255	broadcasthost
::1             localhost

# GitHub520 Host Start
140.82.113.22                 central.github.com
20.205.243.166                github.com
185.199.109.215               github.githubassets.com
# GitHub520 Host End

# 用户手动添加的解析（他人后续修改，含无结尾换行风险行）
9.9.9.9                        time.example.com
EOF

cat > "$SRC" <<'EOF'
# 镜像源注释行（应被丢弃）
1.1.1.1  github.com
2.2.2.2  raw.githubusercontent.com
3.3.3.3  codeload.github.com  # 行内注释应被整体丢弃
EOF

EXPECTED0=$WORK/expected0
non_okra "$HOSTS" > "$EXPECTED0"

echo "=== T1 首次更新 ==="
out=$(run update); rc=$?
check "T1.1 update 退出码 0（rc=${rc}）" ${rc}
grep -q "# Okra Start" "$HOSTS" && grep -q "# Okra End" "$HOSTS"; check "T1.2 Okra 区块已写入" $?
grep -q "1.1.1.1  github.com" "$HOSTS"; check "T1.3 镜像条目 1.1.1.1 github.com 已写入" $?
grep -q "3.3.3.3" "$HOSTS"; [ $? -ne 0 ]; check "T1.4 行内注释行未被当作条目写入" $?

echo "=== T2 更新后他人内容逐字节保留 ==="
non_okra "$HOSTS" > "$WORK/after_update1"
cmp -s "$WORK/after_update1" "$EXPECTED0"; check "T2.1 区块外内容与原文件逐字节一致（含 GitHub520 区块与用户自定义行）" $?

echo "=== T3 他人后续修改（模拟其他工具再改自己的区块） ==="
# 在 GitHub520 区块内追加一行（他人工具更新），再在区块外追加一行（用户手动）
sed -i '' 's|^185.199.109.215               github.githubassets.com$|185.199.109.215               github.githubassets.com\n20.205.243.169                gist.github.com|' "$HOSTS"
printf '8.8.8.8                        dns.example.com\n' >> "$HOSTS"
cp "$HOSTS" "$WORK/hosts-mid"
# 基准：此时文件中除 Okra 区块外的全部行（后续所有"他人内容保留"比对都用它）
non_okra "$WORK/hosts-mid" > "$WORK/expected-mid"

echo "=== T4 二次更新（幂等：无重复区块，他人内容仍保留） ==="
out=$(run update); rc=$?
check "T4.1 二次 update 退出码 0（rc=${rc}）" ${rc}
n=$(grep -c "# Okra Start" "$HOSTS")
[ "${n}" = "1" ]; check "T4.2 Okra 区块唯一（无重复，计数=${n}）" $?
non_okra "$HOSTS" > "$WORK/after_update2"
cmp -s "$WORK/after_update2" "$WORK/expected-mid"; check "T4.3 他人后续修改逐字节保留" $?

echo "=== T5 一键还原 ==="
out=$(run restore); rc=$?
check "T5.1 restore 退出码 0（rc=${rc}）" $rc
grep -q "Okra Start" "$HOSTS" || grep -q "Okra End" "$HOSTS"; [ $? -ne 0 ]; check "T5.2 无 Okra 标记残留" $?
cmp -s "$HOSTS" "$WORK/expected-mid"; check "T5.3 还原后文件与还原前（去 Okra 区块）逐字节一致" $?

echo "=== T6 还原后再次更新（可恢复） ==="
out=$(run update); rc=$?
check "T6.1 还原后 update 退出码 0（rc=${rc}）" ${rc}
grep -q "1.1.1.1  github.com" "$HOSTS"; check "T6.2 区块重新写入" $?
non_okra "$HOSTS" > "$WORK/after_update3"
cmp -s "$WORK/after_update3" "$WORK/expected-mid"; check "T6.3 他人内容仍逐字节保留" $?

echo "=== T7 未装服务时 uninstall 干净报错（非 root） ==="
cp "$HOSTS" "$WORK/hosts-after-t6"
out=$(run uninstall 2>&1); rc=$?
[ ${rc} -ne 0 ]; check "T7.1 非 root uninstall 非零退出（rc=${rc}）" $?
printf '%s' "$out" | grep -q "需要 root"; check "T7.2 错误信息人话化（提示需要 root）" $?
cmp -s "$HOSTS" "$WORK/hosts-after-t6"; check "T7.3 失败卸载未动 hosts（逐字节一致）" $?

echo
echo "结果：${PASS} 通过 / ${FAIL} 失败（共 $((PASS+FAIL)) 项）"
[ ${FAIL} -eq 0 ]