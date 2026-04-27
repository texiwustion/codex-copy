# codex-copy

Copy Codex CLI conversations from zsh.

从 zsh 里复制 Codex CLI 对话。

## Index

- [中文](#中文)
- [English](#english)
- [License](#license)
- [Links](#links)

## 中文

`codex-copy` 是一个很小的 zsh 插件。

它从本地 Codex CLI session 里取出 user / assistant 对话，转成 Markdown，然后复制到剪贴板。

### 安装

直接 source：

```zsh
source /path/to/codex-copy.plugin.zsh
```

或放进本地插件目录：

```zsh
mkdir -p ~/.zsh/plugins/codex-copy
cp codex-copy.plugin.zsh ~/.zsh/plugins/codex-copy/
echo 'source ~/.zsh/plugins/codex-copy/codex-copy.plugin.zsh' >> ~/.zshrc
```

如果你用 zinit：

```zsh
zinit light ~/.zsh/plugins/codex-copy
```

### 用法

```zsh
codex-copy
codex-copy --last
codex-copy 2
codex-copy --session 019dccac
codex-copy --list
```

筛选消息：

```zsh
codex-copy --user
codex-copy --assistant
codex-copy --turn 3
codex-copy --turn -1
codex-copy --from 2 --to 5
```

测试或管道：

```zsh
CODEX_COPY_CLIPBOARD=stdout codex-copy --last
```

### 说明

- 这是 MVP。
- 需要 `zsh` 和 `jq`。
- 默认读取 `${CODEX_HOME:-$HOME/.codex}/sessions/**/*.jsonl`。
- 默认只复制 user / assistant，不复制 tool output。
- 目前只有 `--turn` 支持负数：`--turn -1` 表示最后一轮。
- `--from` / `--to` 只支持正数。
- Codex 本地 session JSONL 不是公开稳定 API，将来可能需要适配。

### 开源说明

完整开源。

无远端服务。

无埋点。

Apache-2.0。

## English

`codex-copy` is a small zsh plugin.

It reads local Codex CLI sessions, extracts user / assistant messages, renders Markdown, and copies it to the clipboard.

### Install

Source it:

```zsh
source /path/to/codex-copy.plugin.zsh
```

Or keep it in a local plugin folder:

```zsh
mkdir -p ~/.zsh/plugins/codex-copy
cp codex-copy.plugin.zsh ~/.zsh/plugins/codex-copy/
echo 'source ~/.zsh/plugins/codex-copy/codex-copy.plugin.zsh' >> ~/.zshrc
```

With zinit:

```zsh
zinit light ~/.zsh/plugins/codex-copy
```

### Usage

```zsh
codex-copy
codex-copy --last
codex-copy 2
codex-copy --session 019dccac
codex-copy --list
```

Filter messages:

```zsh
codex-copy --user
codex-copy --assistant
codex-copy --turn 3
codex-copy --turn -1
codex-copy --from 2 --to 5
```

For tests or pipes:

```zsh
CODEX_COPY_CLIPBOARD=stdout codex-copy --last
```

### Notes

- MVP.
- Requires `zsh` and `jq`.
- Reads `${CODEX_HOME:-$HOME/.codex}/sessions/**/*.jsonl`.
- Copies user / assistant messages by default. Tool output is skipped.
- Only `--turn` supports negative indexes for now. `--turn -1` means the last turn.
- `--from` / `--to` only accept positive indexes.
- Codex local session JSONL is not a stable public API. This may need updates.

### Open source

Fully open.

No remote service.

No telemetry.

Apache-2.0.

## License

Apache License 2.0. See [LICENSE](./LICENSE).

## Links

[![LINUX DO](https://img.shields.io/badge/LINUX%20DO-000000?style=for-the-badge&logo=linux&logoColor=white)](https://linux.do)
