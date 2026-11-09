#!/usr/bin/env python3
"""Run non-invasive AnchorGarden checks without changing SSH on the CI runner."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "vps-anchor.sh"
HARDEN = (ROOT / "vps-harden.sh").read_text()
source = AUDIT.read_text()

subprocess.run(["bash", "-n", str(AUDIT)], check=True)
help_result = subprocess.run(["bash", str(AUDIT), "--help"], text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
assert help_result.returncode == 0
assert "read-only" in help_result.stdout.lower()
assert "effective_kbd" in HARDEN and '"$effective_kbd" != no' in HARDEN
assert "effective_empty" in HARDEN and '"$effective_empty" != no' in HARDEN
assert "ANCHORGARDEN_RESULT" in source
for unsafe in ("systemctl restart", "ufw --force", "passwd -", "sed -i", "apk upgrade"):
    assert unsafe not in source, unsafe

def evaluate(password_auth: str):
    with tempfile.TemporaryDirectory(prefix="anchor-test-") as workdir:
        fake = Path(workdir) / "sshd"
        fake.write_text(
            "#!/bin/sh\n"
            "if [ \"$1\" = \"-V\" ]; then echo 'OpenSSH_9.6p1 mock' >&2; exit 0; fi\n"
            "if [ \"$1\" = \"-T\" ]; then\n"
            "cat <<'SSHD_CONFIG'\n"
            f"passwordauthentication {password_auth}\n"
            "kbdinteractiveauthentication no\n"
            "pubkeyauthentication yes\n"
            "usepam yes\n"
            "permitrootlogin prohibit-password\n"
            "SSHD_CONFIG\n"
            "exit 0\n"
            "fi\n"
            "exit 1\n"
        )
        fake.chmod(0o700)
        path = workdir + os.pathsep + os.environ["PATH"]
        prefix = [] if os.geteuid() == 0 else ["sudo"]
        result = subprocess.run(
            [*prefix, "env", "PATH=" + path, "bash", str(AUDIT)],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
        )
        return result

safe = evaluate("no")
assert safe.returncode in (0, 1), (safe.stdout, safe.stderr)
assert "[HIGH" not in safe.stdout
assert "[PASS" in safe.stdout
unsafe = evaluate("yes")
assert unsafe.returncode == 2, (unsafe.stdout, unsafe.stderr)
assert "SSH password authentication is not disabled" in unsafe.stdout
assert "ANCHORGARDEN_RESULT=HIGH" in unsafe.stdout

print("PASS: AnchorGarden report, read-only guarantees and policy regression checks")
