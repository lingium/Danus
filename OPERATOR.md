# OPERATOR.md — durable operator profile & standing preferences

> Read by the main agent (codex) at the start of every session — it is NOT
> auto-loaded, so `AGENTS.md` tells the agent to read it. It is the main agent's
> **long-term memory of the operator** —
> the things it learns by asking and must not forget when the session ends. Keep it
> short, factual, current; update in place (no duplicates). **No secrets here**
> (tokens/keys go to `config/*.env`, gitignored). This file is committed.
>
> On a fresh deployment this is the blank template — the `initialize` skill fills it.

## Operator
- **Name / how to address:** 凌志
- **Language:** 中文
- **Timezone:** 未指定（当前部署环境为 UTC）

## Standing preferences
- **Notifications:** 未指定
- **Spend ceiling (paid backend API):** 不适用（使用 ChatGPT subscription 后端）
- **worker roster:** `high:3,xhigh:4`（每个项目在 `danus new` 时确认）

## Per-project pointers
_(One line per live project → where its durable facts live. The project's own
problem lives under `runtime/projects/<project>/PROBLEM.md`, not here.)_

## Notes
- Codex backend：自己的 ChatGPT subscription。
- Git 工作分支：`deploy/lingzhi`。