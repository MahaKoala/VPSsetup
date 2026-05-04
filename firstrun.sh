#Quick Manual Run for VPS (no cloud-init)
# MahaKoala/VPSsetup
mkdir -p /etc/vps /usr/local/sbin
curl -fsSL https://raw.githubusercontent.com/<you>/<repo>/main/bootstrap.env -o /etc/vps/bootstrap.env
curl -fsSL https://raw.githubusercontent.com/<you>/<repo>/main/vps-bootstrap.sh -o /usr/local/sbin/vps-bootstrap.sh
curl -fsSL https://raw.githubusercontent.com/<you>/<repo>/main/vps-harden.sh    -o /usr/local/sbin/vps-harden.sh
chmod +x /usr/local/sbin/vps-{bootstrap,harden}.sh

VPS_USER=pink SSH_ID=mahakoala VPS_ROLE=staging \
TAILSCALE_AUTHKEY=tskey-auth-... TAILSCALE_TAGS=tag:vps,tag:staging \
/usr/local/sbin/vps-bootstrap.sh && /usr/local/sbin/vps-harden.sh

# After verifying you can connect via Tailscale
# PUBLIC_SSH_ALLOWED=0 /usr/local/sbin/vps-harden.sh