# ✨ Crush Vibe-Coding on VPSsetup

> **Optional • Multi-provider • Per-user • Cloud-init independent**
>
> Install [Charm Crush](https://github.com/charmbracelet/crush), choose lightweight MCP/LSP profiles, and connect your preferred coding model APIs without placing credentials in cloud-init or GitHub.

| | |
|:---|:---|
| **Installer** | [`vps-vibecode-crush.sh`](vps-vibecode-crush.sh) |
| **Default user** | `$VPS_USER` (not root) |
| **Main entry point** | `vps-init.sh` with `INSTALL_VIBECODE_CRUSH=1` |
| **Direct entry point** | Standalone Crush worker after base user and Homebrew exist |
| **Config format** | `~/.config/crush/crushrc` — [official current format](https://github.com/charmbracelet/crush/blob/main/docs/config/README.md) |
| **Installation default** | **OFF**, including during cloud-init |
| **API credentials** | Read at Crush launch; **never embedded** in generated config |

## 🚀 Quickstart

### Option A — Existing VPS, standalone

If `/etc/vps/bootstrap.env`, your Linux admin user, and Homebrew already exist:

```bash
curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-vibecode-crush.sh \
  -o /tmp/vps-vibecode-crush.sh
bash -n /tmp/vps-vibecode-crush.sh
sudo bash /tmp/vps-vibecode-crush.sh
```

> **Before this PR is merged:** replace `main` with `add-vibecode-crush`, and use `CRUSH_SETUP_REF=add-vibecode-crush` so the worker also downloads the matching configuration assets.

### Option B — Initial one-line installer, no cloud-init required

```bash
sudo env VPS_USER=maha SSH_ID=mahakoala NONINTERACTIVE=1 \
  INSTALL_BREW=1 INSTALL_VIBECODE_CRUSH=1 \
  CRUSH_MCP_PROFILE=core CRUSH_LSP_PROFILE=web,python \
  bash -c 'curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-init.sh | bash'
```

**Selecting this worker does not install the full Claude/Codex/OpenCode/tmuxai/Ollama suite.** The complete suite remains controlled by `INSTALL_TOOLS`.

### Option C — Interactive installer

```bash
curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/vps-init.sh | sudo bash
```

Answer **yes** to *Configure optional Crush vibe-coding tools?*. The wizard enables the Homebrew prerequisite. Answering **no** leaves Crush untouched.

**Cloud-init remains the minimal server bootstrap:** `cloud-init.yaml` is not changed and continues with `INSTALL_TOOLS=0`, with no Crush-specific installation.

---

## 🧩 Installation profiles

| Variable | Default | Choices / meaning |
|:---|:---|:---|
| `INSTALL_VIBECODE_CRUSH` | `0` | Enable worker in `vps-init.sh` only |
| `CRUSH_MCP_PROFILE` | `core` | `none`, `core` (Context7), `extended` (Context7 + memory, thinking, fetch, git) |
| `CRUSH_LSP_PROFILE` | `web,python` | Any of `web,python,go,rust` or `none` |
| `CRUSH_INSTALL_ROOT` | `0` | Explicitly configure Crush for root too (not recommended) |
| `CRUSH_CONFIG_ONLY` | `0` | `1` stages config without installing any packages |
| `CRUSH_INSTALL_BIN` | `1` | `0` avoids reinstalling the Crush binary |
| `CRUSH_OVERWRITE_COMMANDS` | `0` | `1` replaces existing custom command files |
| `CRUSH_SETUP_REF` | `VPS_SETUP_REF` | Repository tag/commit/branch for matching managed assets |

**Core** loads only Context7. The full filesystem MCP is intentionally **not global**, because giving every session access to all of `$HOME` may expose SSH credentials or other sensitive files.

**Extended** adds `uvx`-based fetch/git and Node-based memory/reasoning servers; first launch can be slower. For front-end work, copy an opt-in project template.

### LSP selection

| Profile | Installs / configures |
|:---|:---|
| `web` | vtsls, Biome, Node/npm |
| `python` | basedpyright, Ruff |
| `go` | gopls |
| `rust` | rust-analyzer |

Only requested languages are installed. Provider models run remotely, so a 4 GB VPS doesn't need local model weights.

---

## 🌐 Supported AI model providers

Set credentials in the **launching user's environment** using your preferred secrets manager. **Do not** paste keys into `bootstrap.env`, `crushrc`, GitHub, or provider user-data. Provider entries are activated only when their credential exists.

| Provider | Environment variable | API endpoint | Suggested model |
|:---|:---|:---|:---|
| Anthropic Claude | `ANTHROPIC_API_KEY` | Native Anthropic | Use Crush model picker |
| OpenAI | `OPENAI_API_KEY` | Native OpenAI | Use Crush model picker |
| OpenRouter | `OPENROUTER_API_KEY` | `openrouter.ai/api/v1` | Available models via discovery |
| Moonshot / Kimi (pay-as-you-go) | `MOONSHOT_API_KEY` | `api.moonshot.ai/v1` | `kimi-k2.6`; K2 preview may be legacy |
| **Kimi Code** membership | `KIMI_CODE_API_KEY` | `api.kimi.ai/coding/v1` | Coding-plan model list |
| **Z.ai / GLM** general | `ZAI_API_KEY` | `api.z.ai/api/paas/v4` | `glm-5.3` |
| **Z.ai Coding Plan** | `ZAI_CODING_API_KEY` | `api.z.ai/api/coding/paas/v4` | Plan-authorized GLM |
| **Zhipu BigModel** | `ZHIPU_API_KEY` | `open.bigmodel.cn/api/paas/v4` | `glm-5.3` |
| Zhipu Coding Plan | `ZHIPU_CODING_API_KEY` | `open.bigmodel.cn/api/coding/paas/v4` | Plan-authorized GLM |
| **xAI Grok** | `XAI_API_KEY` | `api.x.ai/v1` | `grok-4.7` |
| **DeepSeek** | `DEEPSEEK_API_KEY` | `api.deepseek.com` | `deepseek-v4-pro`, `deepseek-flash` |

The installer does not verify purchased quotas or charge your account. Use the current model picker to select an authorized model. Models and plans change independently of VPSsetup.

**Distinctions:** Kimi Code and Moonshot keys are not interchangeable. Z.ai Coding Plan uses a different billing endpoint from prepaid API access. The same separation applies to Zhipu BigModel. See [Kimi Code](https://www.kimi.com/code/docs/en/), [Z.ai](https://zcode.z.ai/en/docs/configuration), [DeepSeek](https://api-docs.deepseek.com/), and [xAI](https://docs.x.ai/developers/models) documentation.

### DeepSeek Super-Agent is different from DeepSeek API

[DeepSeek's `dsh-superagent-prototype`](https://github.com/deepseek-ai/dsh-superagent-prototype) is a **research prototype**, not a `model` ID or a built-in Crush provider. Its own README states it is **not an official product and not production ready**. It is documented here as a separate experimental agent harness and **is not cloned, executed, or granted GitHub credentials** by the Crush installer. Review its trust boundaries and dedicated-user setup before exploring it on a disposable VM.

---

## 📁 Generated configuration

```text
~/.config/crush/
├── crushrc                       ← your entry point (preserved)
├── vpssetup-managed.crushrc      ← generated sources; updated on re-run
├── vpssetup.d/
│   ├── providers.crushrc         ← runtime environment variables, no tokens
│   ├── core.crushrc
│   ├── extended.crushrc
│   └── lsp/{web,python,go,rust}.crushrc
├── commands/
│   ├── plan.md
│   ├── ship.md
│   ├── review.md
│   ├── debug.md
│   └── scaffold.md
└── templates/
    ├── frontend.crushrc
    └── deploy.crushrc
```

The worker uses `install -m 600`, preserves an existing `crushrc`, appends a managed include only when missing, and doesn't overwrite existing commands unless explicitly allowed. It updates only its own managed files.

### Opt into project MCPs

From a trusted project directory:

```bash
cp ~/.config/crush/templates/frontend.crushrc ./crushrc
# Or select the optional GitHub deployment MCP instead:
cp ~/.config/crush/templates/deploy.crushrc ./crushrc
```

Review the generated `crushrc` before running `crush` in that directory. Project-level configuration is executable Bash, and enabling third-party MCPs can grant code execution, file access, or network access. Deployment access should use short-lived, least-privilege tokens.

### Re-run safely

```bash
sudo /usr/local/sbin/vps-vibecode-crush.sh
# Or deploy configuration only (no package updates):
sudo CRUSH_CONFIG_ONLY=1 /usr/local/sbin/vps-vibecode-crush.sh
```

For troubleshooting, check `/var/log/vps-bootstrap.log`, verify `crush --version` as `$VPS_USER`, and check the selected model in the Crush picker. All provider configurations rely on the account's actual API permissions; Crush is not silently authenticated for you.

---

## 🔗 Further reading

- [VPSsetup architecture](README_VPSscripts.md) · [One-line installer](README_SingleFileVPSinit.md) · [Main README](README.md)
- [Crush configuration](https://github.com/charmbracelet/crush/blob/main/docs/config/README.md)
- [Crush source](https://github.com/charmbracelet/crush)
- [DeepSeek Super-Agent prototype](https://github.com/deepseek-ai/dsh-superagent-prototype)
