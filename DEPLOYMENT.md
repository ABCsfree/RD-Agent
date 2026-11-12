# RD-Agent 部署指南（实战踩坑版）

> 本文档来自一次完整的真实部署验证（Windows 原生 → WSL Ubuntu → 跑通 A 股因子自动迭代全链路），
> 覆盖 Linux、WSL2、Windows 三个平台，以及 LLM 配置、Qlib 数据、Web UI、日常运维的全部已知坑。
> 按本文档走，新机器从零到跑起 `fin_factor` 约需 40-60 分钟（含数据下载）。

## TL;DR：平台怎么选

| 你的系统 | 推荐路径 | 原因 |
|---|---|---|
| **Linux** | 原生部署（本文主路径） | 官方唯一支持的环境，零平台坑 |
| **Windows** | **WSL2 + Ubuntu**（本文主路径同样适用） | Windows 原生跑不通（见下方硬伤清单），WSL 是官方支持的替代 |
| macOS | 未验证 | 大坑理论通用，小坑未知 |

**Windows 原生部署的硬伤（实测确认，不要尝试）**：
1. `rdagent/components/coder/factor_coder/config.py` 硬编码 `CondaConf(conda_env_name=os.environ.get("CONDA_DEFAULT_ENV"))`，无默认值——非 conda 环境直接校验崩溃；
2. `rdagent/utils/env.py` 的 `LocalEnv._run` 用 `:` 拼 PATH 并硬编码 `/bin/`、`/usr/bin/`，Windows 的 cmd 无法解析，任何本地组件执行必挂；
3. 工作区大量使用 symlink（Windows 需要特权）、路径分隔符与 bash 假设遍布全链路。

以上任何一条都足以让 `fin_factor` 中途崩溃，且修复无底洞——**Windows 用户请直接走 WSL2**。

---

## 一、环境要求

- Python ≥ 3.10（3.10-3.14 实测可装依赖；注意 pyqlib 数据工具需要 ≤ 3.11，见数据章节）
- Git
- Docker（量化场景回测在容器里跑）
- Node.js ≥ 18 + npm（仅 Web UI 前端构建需要）
- LLM API：chat（支持 json mode）+ embedding 各一个

## 二、部署步骤（Linux / WSL Ubuntu 通用）

### 0.（仅 WSL）装 Ubuntu 并打通 Docker Desktop 集成

```powershell
wsl --install -d Ubuntu --no-launch    # 不进入首次用户创建，后续都用 root
wsl --set-default Ubuntu
```

Docker Desktop 的 WSL 集成（新装的发行版默认**不**自动集成）：
打开 Docker Desktop → Settings → Resources → WSL Integration → 勾选你的发行版。
如果改配置文件：`%AppData%\Docker\settings-store.json` 中键名必须用 **PascalCase**
（`"EnableIntegrationWithDefaultWslDistro": true`、`"IntegratedWslDistros": ["Ubuntu"]`），
camelCase 键会被静默忽略——这是官方文档没写的坑。

（仅 WSL）建议加内存限制 `C:\Users\<你>\.wslconfig`：

```ini
[wsl2]
memory=16GB
swap=8GB
[experimental]
autoMemoryReclaim=gradual
```

`wsl --shutdown` 后生效。`autoMemoryReclaim` 防止 vmmem 钉死不还内存（实测 25GB 占用 → 4.7GB）。

### 1. 克隆并安装

```bash
git clone https://github.com/<你的fork>/RD-Agent.git
cd RD-Agent
python3 -m venv .venv
.venv/bin/pip install --upgrade pip setuptools wheel
.venv/bin/pip install -e .
```

### 2. 配置 .env

```bash
cp .env.example .env
# 编辑 .env，两套验证过的方案任选其一（key 用你自己的）
```

配置结构、模型名、豁免变量等细节全部在 `.env.example` 的注释里，这里只强调三条**血泪坑**：

1. **不要混用 `OPENAI_API_BASE/KEY` 和 `litellm_proxy/` 前缀**——litellm 的通用 OPENAI_* 变量会劫持 litellm_proxy 路由（base 和 key 都覆盖），embedding 静默打到错误地址。chat 走网关时请用 `deepseek/` 前缀 + `DEEPSEEK_API_BASE/KEY`（变量对完全隔离）。
2. **shell 里若已存在同名（哪怕为空的）`OPENAI_API_KEY` / `OPENAI_BASE_URL`**，`load_dotenv` 不会覆盖它们，你的 key 永远加载不进去。先 `unset`（或从系统环境变量里删除）。
3. 网关模型报 `No available channel for model X under group Y` = 该模型在你的分组下无渠道（key 有效但模型没配），换模型名或问服务商，别怀疑 RD-Agent。

### 3. 启动器 + conda shim（无 conda 环境必备）

RD-Agent 假设你在 conda 环境里跑（读 `CONDA_DEFAULT_ENV`），没装 conda 时用两个小补丁绕过：

```bash
# 3.1 conda shim：响应 CondaConf 的 PATH 探测，指向 venv
#    (deploy/conda-shim.sh，需将其中的 <REPO_PATH> 替换为仓库绝对路径)
sudo cp deploy/conda-shim.sh /usr/local/bin/conda && sudo chmod +x /usr/local/bin/conda

# 3.2 启动器：deploy/run.sh（已在仓库内，含说明注释）
cp deploy/run.sh ./run.sh && chmod +x run.sh
./run.sh health_check    # 必须四项全绿再继续
```

`run.sh` 做了四件事：设 `CONDA_DEFAULT_ENV`（过校验）、`MODEL_COSTEER_ENV_TYPE=docker`（回测走 Docker，不需要本地 conda）、`UI_SERVER_AUTH_TOKEN`、PATH 指向 venv。

### 4. 准备 Qlib A 股数据（关键且官方文档没写全的一步）

`fin_factor` 需要 `~/.qlib/qlib_data/cn_data`（约 520MB）。两个坑：
- RD-Agent 的**自动下载命令是坏的**（`python -m qlib.run.get_data` 在 pyqlib 0.9.7 里不存在，失败被静默吞掉，之后回测报 `does not contain data for day`）；
- **pyqlib 只发布 cp38-cp312 的 wheel**，Python 3.13/3.14 装不上。

正确姿势：

```bash
# 独立的 Python 3.11 环境装 pyqlib（用 uv 最省事）
curl -LsSf https://astral.sh/uv/install.sh | sh
~/.local/bin/uv venv --python 3.11 ~/qlibdl
~/.local/bin/uv pip install --python ~/qlibdl/bin/python pyqlib

# 用 GitHub 仓库里的官方下载脚本（不是 pip 包里的模块）
curl -sL -o ~/get_data.py https://raw.githubusercontent.com/microsoft/qlib/main/scripts/get_data.py
~/qlibdl/bin/python ~/get_data.py qlib_data \
  --target_dir ~/.qlib/qlib_data/cn_data --region cn --interval 1d --delete_old False
```

数据目录必须包含 `calendars/ features/ instruments/` 三件套。之后 RD-Agent 会打印 `Data already exists. Download skipped.`

### 5. 构建 Web UI 前端（可选但推荐）

```bash
sudo apt install -y nodejs npm        # Ubuntu 24.04+ 自带的版本即可
cd web
npm install --legacy-peer-deps        # 必须！vite 8 与插件的 peer 声明冲突
npm run build:flask                   # 产物输出到 ../git_ignore_folder/static
```

### 6. 启动

```bash
# 因子迭代（nohup 常驻，防终端/会话回收杀进程）
nohup ./run.sh fin_factor > ~/fin_factor.log 2>&1 < /dev/null &

# Web UI（另开终端）
nohup ./run.sh server_ui > ~/server_ui.log 2>&1 < /dev/null &
```

浏览器打开 `http://localhost:19899/?token=<你的UI_SERVER_AUTH_TOKEN>`（首次带 token 会种 cookie）。

验证在跑：`tail -f ~/fin_factor.log`，看到 `Data already exists. Download skipped.` 和因子假设的 LLM 输出即为正常。

## 三、坑总清单（速查表）

| # | 症状 | 根因 | 解法 |
|---|---|---|---|
| 1 | `ValidationError: CondaConf.conda_env_name` 崩溃 | 非 conda 环境无 `CONDA_DEFAULT_ENV` | run.sh 设变量 + conda shim |
| 2 | Windows 原生组件执行全挂 | PATH 用 `:` 拼接、`/bin/` 硬编码 | 用 WSL/Linux，别修源码 |
| 3 | embedding 请求打到 chat 的网关 | litellm 的 OPENAI_* 劫持 litellm_proxy 路由 | chat 用 `deepseek/` 前缀变量对 |
| 4 | chat 报 missing credentials | shell 里有遗留的空 OPENAI_API_KEY | unset 后再启动 |
| 5 | `Invalid port: ':1]'`（Windows） | NO_PROXY 含 `[::1]` | `$env:NO_PROXY='localhost,127.0.0.1'` |
| 6 | 日志刷 UnicodeEncodeError（Windows） | GBK 控制台显示不了 emoji | `PYTHONUTF8=1` |
| 7 | WSL 里 docker 命令不存在 | Docker Desktop 集成未覆盖新发行版 | 见一.0 节 |
| 8 | `does not contain data for day` | Qlib 数据没准备（自动下载是坏的） | 二.4 节手动下载 |
| 9 | pyqlib 装不上 | 只发布到 cp312 | uv + Python 3.11 |
| 10 | 回测报 mlflow `maintenance mode` | mlflow 新版弃用 FileStore | 本仓库 Dockerfile 已加 `ENV MLFLOW_ALLOW_FILE_STORE=true`（拉了本 fork 即免疫） |
| 11 | server_ui 启动报 ValueError | 新版要求 `UI_SERVER_AUTH_TOKEN` | .env 里配（见 .env.example） |
| 12 | Web UI 打开 404 | 前端没构建 | `npm run build:flask` |
| 13 | npm install 报 ERESOLVE | vite 8 与 plugin-vue peer 声明冲突 | `--legacy-peer-deps` |
| 14 | 进程莫名消失 | 挂在终端/IDE 会话上被回收 | nohup 常驻启动 |
| 15 | vmmem 内存疯涨不降 | WSL2 页缓存不归还 | `.wslconfig` + `autoMemoryReclaim` |
| 16 | `pkill -f` 把自己 shell 杀了 | 模式匹配到自身命令行 | 用 `pkill -f '[r]dagent ...'` 字符类技巧 |

## 四、日常运维

```bash
# 看日志 / 看进程
tail -f ~/fin_factor.log
ps aux | grep '[r]dagent'

# 停止因子迭代
pkill -f '[r]dagent fin_factor'

# 重启（或开机后启动，两条命令）
nohup ./run.sh fin_factor > ~/fin_factor.log 2>&1 < /dev/null &
nohup ./run.sh server_ui > ~/server_ui.log 2>&1 < /dev/null &

# 数据更新（A 股每日收盘后，重跑下载命令即可拉最新快照）
~/qlibdl/bin/python ~/get_data.py qlib_data \
  --target_dir ~/.qlib/qlib_data/cn_data --region cn --interval 1d --delete_old False
```

迭代产物（因子代码、回测结果、trace）都在 `git_ignore_folder/RD-Agent_workspace/` 下按 session 归档，Web UI 是它们的前端。

## 五、进阶

- **中文输出**：`.env` 里取消注释 `DEFAULT_SYSTEM_PROMPT`（见 .env.example），LLM 的假设/分析/反馈会用简体中文。注意部分组件用自定义 prompt 模板（`rdagent/scenarios/qlib/prompts.yaml`），要全量中文化需要改模板。
- **模型迭代**：跑顺 `fin_factor` 后可试 `fin_quant`（因子-模型联合进化），同一套环境直接可用。
- **样本外验证铁律**：自动迭代容易过拟合，任何因子实盘前务必用迭代过程从未接触的样本外数据做 walk-forward 验证。
