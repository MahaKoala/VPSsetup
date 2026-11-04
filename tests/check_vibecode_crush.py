#!/usr/bin/env python3
"""Non-destructive checks for optional Crush + DeepSeek research workers."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
installer = (ROOT / "vps-init.sh").read_text()
defaults = (ROOT / "bootstrap.env").read_text()
cloud_init = (ROOT / "cloud-init.yaml").read_text()
crush_worker = (ROOT / "vps-vibecode-crush.sh").read_text()
superagent_worker = (ROOT / "vps-deepseek-superagent.sh").read_text()

assert 'INSTALL_VIBECODE_CRUSH="${INSTALL_VIBECODE_CRUSH:-0}"' in defaults
assert 'STAGE_DEEPSEEK_SUPERAGENT="${STAGE_DEEPSEEK_SUPERAGENT:-0}"' in defaults
assert "INSTALL_VIBECODE_CRUSH" not in cloud_init, "Crush must stay out of cloud-init"
assert "STAGE_DEEPSEEK_SUPERAGENT" not in cloud_init, "Research worker must stay out of cloud-init"
assert 'if [[ "${INSTALL_VIBECODE_CRUSH:-0}" == "1" ]]' in installer
assert 'if [[ "${STAGE_DEEPSEEK_SUPERAGENT:-0}" == "1" ]]' in installer
assert 'download "vps-vibecode-crush.sh"' in installer
assert 'download "vps-deepseek-superagent.sh"' in installer

for worker in ("vps-vibecode-crush.sh", "vps-deepseek-superagent.sh"):
    subprocess.run(["bash", "-n", str(ROOT / worker)], check=True)

assets = list((ROOT / "vibecode-crush").rglob("*.crushrc"))
assert len(assets) >= 8, "Expected provider, MCP, LSP, and project configs"
for asset in assets:
    subprocess.run(["bash", "-n", str(asset)], check=True)
    assert asset.stat().st_size > 0

for command in ("plan", "ship", "review", "debug", "scaffold"):
    assert (ROOT / "vibecode-crush" / "commands" / f"{command}.md").exists()

providers = (ROOT / "vibecode-crush" / "providers.crushrc").read_text()
for key in (
    "MOONSHOT_API_KEY", "KIMI_CODE_API_KEY", "ZAI_API_KEY",
    "ZAI_CODING_API_KEY", "ZHIPU_API_KEY", "ZHIPU_CODING_API_KEY",
    "XAI_API_KEY", "DEEPSEEK_API_KEY", "OPENROUTER_API_KEY",
    "ANTHROPIC_API_KEY", "OPENAI_API_KEY",
):
    assert key in providers, key
for url in (
    "https://api.moonshot.ai/v1", "https://api.kimi.ai/coding/v1",
    "https://api.z.ai/api/coding/paas/v4", "https://api.z.ai/api/paas/v4",
    "https://api.x.ai/v1", "https://api.deepseek.com",
):
    assert url in providers, url
assert "dsh-superagent" not in providers, "Super-Agent is not a model/provider"
assert "DEEPSEEK_API_KEY" not in superagent_worker
assert "git clone" in superagent_worker
assert "npm install" not in superagent_worker
assert "docker run" not in superagent_worker
assert "runuser -u" in superagent_worker
assert "CRUSH_INSTALL_ROOT:=0" in crush_worker
assert "CRUSH_CONFIG_ONLY:=0" in crush_worker
assert "crushrc" in crush_worker and "vpssetup-managed.crushrc" in crush_worker
assert (ROOT / "README_VibecodeCrush.md").exists()

print("PASS: optional worker flags, multi-provider assets, config syntax and safe research staging")
