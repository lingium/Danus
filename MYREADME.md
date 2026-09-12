

| 配置 | 控制范围 |
|---|---|
| `.codex/config.toml` 的 `model`、`model_reasoning_effort` | 主交互会话，即打开 ./bin/codex 聊天用的 |
| `.codex/config.toml` 的 `review_model` | Codex `/review` |
| `config/danus.env` 的 `DANUS_MAIN_MODEL/EFFORT` | 后台 worker、验证器、渲染器的默认值；专用覆盖项优先 |
第3个 The DANUS_* 用于Danus 程序自动启动的、非交互式的 Codex 任务，主要包括：
worker 执行证明任务；
verifier 检查候选证明；
论文、报告生成器执行写作任务。


配置完成后，新终端直接进入仓库根目录，
运行 ./bin/codex 即可
它会自动加载已安装的运行环境；首次安装依赖由 bootstrap 完成。

执行 bin/codex
  → scripts/env.sh 加载环境、定位仓库和 Python
  → 设置隔离的 CODEX_HOME
  → scripts/codex-paths.py 更新路径配置
  → 启动真正的 Codex CLI

刚 clone 的全新目录应该怎么做？
```
cd /新路径/Danus
bash scripts/bootstrap-mac.sh
它会创建 venv、安装依赖、生成运行环境配置和隔离的 Codex home，并创建缺失的 .env 配置文件。
```
首次安装时，`config/codex-home.config.toml.example` 会被复制到
`runtime/codex-home/config.toml`，默认使用 `danus-only` 权限规则。
再次运行 bootstrap 会保留已有配置。仓库路径由 `scripts/codex-paths.py`
自动生成；模型设置统一在项目的 `.codex/config.toml` 中维护。

接着检查两类设置：
- .codex/config.toml：主交互会话的模型、推理强度。
- config/danus.env：后台任务的模型、服务配置。当前 macOS bootstrap 默认选择 ChatGPT 登录。


```
新的 clone 有独立的 runtime/codex-home，因此需要为它登录
bash scripts/setup-codex.sh login
bash scripts/check-codex.sh

bash scripts/services.sh up verify
bash scripts/doctor.sh
./bin/codex

首次正式使用 Danus 时，再完成仓库的 initialize 流程，记录操作人偏好及初始化状态
```

