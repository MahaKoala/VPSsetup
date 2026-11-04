#!/usr/bin/env python3
"""Static provisioning parity checks: safe to run without root or a VPS."""
from pathlib import Path
import subprocess

import yaml

ROOT = Path(__file__).resolve().parents[1]
cloud_path = ROOT / "cloud-init.yaml"
cloud = cloud_path.read_bytes()
assert cloud.startswith(b"#cloud-config\n"), "cloud-init must start on line one"
assert len(cloud) < 32 * 1024, "Hetzner user-data exceeds 32 KiB"
parsed = yaml.safe_load(cloud)
assert isinstance(parsed["write_files"], list)
assert "runcmd" in parsed
files = {entry["path"]: entry["content"] for entry in parsed["write_files"]}
assert "/etc/vps/bootstrap.env" in files
assert "/usr/local/sbin/hetzner-firstboot.sh" in files

config = files["/etc/vps/bootstrap.env"]
for setting in (
    "VPS_USER=", "VPS_HOSTNAME=", "SSH_ID=", "SSH_ID_TYPED_KEYS=",
    "FIRST_LOGIN_PASSWORD_PROMPT=", "SWAP_MODE=", "SWAP_PERCENT=",
    "TAILNET_SSH_VERIFIED=", "VPS_SETUP_REF=",
):
    assert setting in config, setting

worker_names = (
    "vps-swap.sh", "vps-bootstrap.sh", "vps-harden.sh",
    "vps-tools.sh", "VerifyChecklist.sh",
)
installer = (ROOT / "vps-init.sh").read_text()
assert "cloud-init" not in installer.lower().splitlines()[-1], "unexpected"
for worker in worker_names:
    assert (ROOT / worker).exists(), worker
    assert worker in installer, f"installer must fetch {worker}"
    subprocess.run(["bash", "-n", str(ROOT / worker)], check=True)

for entrypoint in ("vps-init.sh", "firstrun.sh", "addnew-sshid-key.sh", "addupdate-sshid-key.sh"):
    subprocess.run(["bash", "-n", str(ROOT / entrypoint)], check=True)

assert "vps-init.sh" in files["/usr/local/sbin/hetzner-firstboot.sh"]
assert "vps-bootstrap.sh" not in files["/usr/local/sbin/hetzner-firstboot.sh"]
assert "vps-init.sh" in (ROOT / "firstrun.sh").read_text()
assert "BOOTSTRAP_EOF" not in installer, "do not embed duplicate workers"
assert "HARDEN_EOF" not in installer
assert "Protocol 2" not in (ROOT / "vps-harden.sh").read_text()
assert "ufw --force reset" not in (ROOT / "vps-harden.sh").read_text()
assert "TAILNET_SSH_VERIFIED" in (ROOT / "vps-harden.sh").read_text()
assert "FIRST_LOGIN_PASSWORD_PROMPT" in (ROOT / "vps-bootstrap.sh").read_text()
assert "ECDSA-SK" in (ROOT / "vps-bootstrap.sh").read_text()

script = ROOT / "tests" / "_firstboot_extracted.sh"
try:
    script.write_text(files["/usr/local/sbin/hetzner-firstboot.sh"])
    subprocess.run(["bash", "-n", str(script)], check=True)
finally:
    script.unlink(missing_ok=True)

# Reference documentation must accompany portable provisioning.
assert (ROOT / "docs" / "HETZNER.md").exists()
assert "tcp:22" in (ROOT / "tailscale.json").read_text()
print(f"PASS: cloud-init {len(cloud)} bytes, independent workers, shell syntax and safety invariants")
