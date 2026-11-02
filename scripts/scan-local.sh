#!/usr/bin/env bash
# 在本机对某个项目仓库跑和 CI 一样的检查 (只需要 Docker)
#
#   scripts/scan-local.sh ../cpp-common              # 全部
#   scripts/scan-local.sh ../cpp-common test         # 只跑某几项: secrets | sast | test
#
# test 会在 Ubuntu 24.04 + clang-18 容器里分别用 普通 / ASan+UBSan / TSan 编译并跑 ctest
set -uo pipefail

HERE=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "${1:?用法: scan-local.sh <项目仓库目录> [secrets|sast|test]...}" && pwd)
shift
WF="$HERE/.github/workflows/cpp.yml"
img() { sed -n "s/^  $1: //p" "$WF"; }   # 扫描器版本从 cpp.yml 读，保证和 CI 一致
GITLEAKS=$(img GITLEAKS_IMAGE)
SEMGREP=$(img SEMGREP_IMAGE)
CI_IMAGE=cpp-ci:local

failed=()
run() {   # run <名字> <命令...>: 失败不中断，最后汇总
  local name=$1; shift
  echo -e "\n=== $name"
  "$@" || failed+=("$name")
}
want() { [[ $# -eq 0 || " $* " == *" $STEP "* ]]; }

step_secrets() {
  # 本地扫工作目录 (没提交的文件也算)；CI 扫完整 git 历史
  run gitleaks docker run --rm -v "$REPO":/repo "$GITLEAKS" \
    dir /repo --redact --no-banner
}

step_sast() {
  local py=()
  [[ -n $(find "$REPO" -name '*.py' -not -path '*/build*' | head -1) ]] && py=(--config p/python)
  run semgrep docker run --rm -v "$REPO":/src -w /src "$SEMGREP" semgrep scan \
    --config p/c --config p/github-actions ${py[@]+"${py[@]}"} --metrics=off --error
}

step_test() {
  docker build -q -t "$CI_IMAGE" -f "$HERE/docker/ci.Dockerfile" "$HERE/docker" > /dev/null || {
    failed+=(ci-image); return; }
  local san flags
  for san in none address thread; do
    case $san in
      address) flags="-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer" ;;
      thread)  flags="-fsanitize=thread" ;;
      *)       flags="" ;;
    esac
    # 源码只读挂载，构建目录放在容器里，不污染本机的 build/
    # TSan 要关掉 ASLR (setarch -R)，这需要放开 seccomp 对 personality 调用的限制
    run "test-$san" docker run --rm --security-opt seccomp=unconfined \
      -v "$REPO":/src:ro -e FLAGS="$flags" "$CI_IMAGE" setarch -R sh -c '
        cmake -S /src -B /tmp/b -DCMAKE_BUILD_TYPE=RelWithDebInfo \
          -DCMAKE_CXX_FLAGS="$FLAGS" -DCMAKE_EXE_LINKER_FLAGS="$FLAGS" > /dev/null &&
        cmake --build /tmp/b > /dev/null &&
        ctest --test-dir /tmp/b --output-on-failure'
  done
}

for STEP in secrets sast test; do
  want "$@" && "step_$STEP"
done

echo
if ((${#failed[@]})); then echo "FAILED: ${failed[*]}"; exit 1; fi
echo "ALL PASSED"
