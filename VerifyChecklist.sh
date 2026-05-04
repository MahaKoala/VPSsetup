ssh pink@<server-ip>          # or via Tailscale: ssh pink@<tailscale-name>
hostnamectl
brew doctor
tailscale status
sudo ufw status verbose
sudo fail2ban-client status sshd
systemctl status unattended-upgrades

# Logs: `/var/log/vps-bootstrap.log` contains the full output of both scripts.