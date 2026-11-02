# devsecops-pipelines

所有 C++ 项目共用的 DevSecOps 流水线。流水线只在这里写一份，各项目仓库用几行代码调用。

这就是大公司平台团队给业务团队提供"黄金流水线 (golden pipeline)"的做法：
- 安全检查统一，不会有哪个项目漏掉
- 升级扫描器只改这里一处，各项目通过 Dependabot 自动收到更新 PR

## 包含哪些检查

| Job | 工具 | 失败条件 |
|---|---|---|
| `secrets` | gitleaks，扫完整 git 历史 | 发现任何密钥 |
| `sast` | Semgrep：C/C++、GitHub Actions 规则，有 Python 时加 Python 规则 | 任何发现 |
| `codeql` | CodeQL `security-extended`：C++、Actions，可选 Python | 有告警 (在 Security 页面查看) |
| `test` | clang-18 分别做 **普通 / ASan+UBSan / TSan** 三种构建，然后跑 ctest | 测试失败，或 sanitizer 报错 |

扫描结果上传到各仓库的 **Security → Code scanning**。

## 项目怎么接入

**约定**：仓库根目录有 `CMakeLists.txt`，测试用 `add_test` 注册到 ctest。

在项目仓库加 `.github/workflows/ci.yml`：

```yaml
name: ci
on:
  push: { branches: [main] }
  pull_request:
  schedule: [{ cron: '0 3 * * 1' }]
permissions:
  contents: read
jobs:
  devsecops:
    uses: hwang-protocol/devsecops-pipelines/.github/workflows/cpp.yml@<commit SHA>
    permissions:
      contents: read
      security-events: write
    with:
      apt-packages: libsqlite3-dev   # 可选
      python: true                   # 可选：有 Python 脚本时
```

**为什么用 commit SHA 而不是 `@main`**：和固定第三方 Action 的理由一样。
如果写 `@main`，有人改了这个仓库，所有项目下次运行时会立刻执行新代码，没有任何审查机会。

## 输入参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `apt-packages` | 空 | 额外的系统依赖，空格分隔 |
| `cmake-args` | 空 | 额外的 cmake 配置参数 |
| `python` | `false` | 仓库里有 Python 脚本时设为 `true` |

## 本地运行

所有仓库都放在同一个上级目录 `repos/` 下：

```bash
cd repos/devsecops-pipelines

# 对某个项目跑全部检查
scripts/scan-local.sh ../cpp-common

# 只跑其中几项: secrets | sast | test
scripts/scan-local.sh ../cpp-common test
```

`test` 在 [docker/ci.Dockerfile](docker/ci.Dockerfile) 定义的 Ubuntu 24.04 + clang-18 容器里运行，和 GitHub 的 runner 环境一致。
所以在 Mac 上也能验证 Linux 下的编译和 sanitizer 结果。

## 本仓库自己的检查

[self-check.yml](.github/workflows/self-check.yml) 用 actionlint 检查工作流文件的语法和其中的 shell 脚本。
