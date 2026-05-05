#!/usr/bin/env bash
# install-vpsview.sh — install vpsview, a Charm/Bubbletea TUI VPS dashboard.
#
# What you get
#   /usr/local/bin/vpsview — interactive TUI showing:
#     • CPU / MEM / DISK live gauges
#     • CPU + network in/out 60-second sparkline history
#     • Listening ports & services (ss / lsof)
#     • Disks table (df -h, virtual fs filtered)
#     • Detected AI CLIs with versions (claude, opencode, codex, tmuxai, ollama, …)
#     • Uptime + load average + hostname/user banner
#   Keys: q quit · r refresh · ? help
#
# Usage (any of these work):
#   bash install-vpsview.sh
#   sudo bash install-vpsview.sh
#   bash <(curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/install-vpsview.sh)
#   curl -fsSL https://raw.githubusercontent.com/MahaKoala/VPSsetup/main/install-vpsview.sh | bash
#
# Requirements
#   • Ubuntu/Debian with apt-get
#   • sudo (for apt install of golang and final binary install to /usr/local/bin)
#   • ~150 MB disk space for Go workspace (cached at $HOME/.local/src/vpsview for faster rebuilds)
#   • 60–120 seconds for first-time build (subsequent rebuilds are ~10 s thanks to module cache)
#
# Idempotent — safe to re-run; reuses workspace cache and overwrites the binary.

set -Eeuo pipefail

APP_NAME="vpsview"
INSTALL_BIN="/usr/local/bin/$APP_NAME"
WORKDIR="${VPSVIEW_WORKDIR:-$HOME/.local/src/$APP_NAME}"

# sudo only when we're not already root
need_sudo() { [ "$(id -u)" -ne 0 ] && echo sudo || true; }
SUDO="$(need_sudo)"

# ---------- prerequisites ----------
echo "[*] Installing apt prerequisites (golang, build-essential, lsof)…"
if ! command -v apt-get >/dev/null 2>&1; then
    echo "ERROR: this installer supports apt-based systems (Ubuntu/Debian)." >&2
    echo "       For other distros, install Go ≥1.22 manually and 'go build' the source below." >&2
    exit 1
fi
$SUDO apt-get update -y -qq
$SUDO apt-get install -y --no-install-recommends \
    git build-essential pkg-config golang-go lsof

if ! command -v go >/dev/null 2>&1; then
    echo "ERROR: 'go' not in PATH after apt install. Try a fresh shell." >&2
    exit 1
fi

go_v=$(go version | awk '{print $3}' | sed 's/^go//')
go_major=$(echo "$go_v" | cut -d. -f1)
go_minor=$(echo "$go_v" | cut -d. -f2)
if (( go_major < 1 || (go_major == 1 && go_minor < 22) )); then
    echo "ERROR: Go ≥1.22 required (have: $go_v)." >&2
    echo "       On older Ubuntu: sudo apt install golang-1.22-go" >&2
    exit 1
fi
echo "[*] Go version: $go_v ✓"

# ---------- workspace ----------
echo "[*] Workspace: $WORKDIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

cat > go.mod <<'EOF'
module vpsview

go 1.22

require (
    github.com/charmbracelet/bubbletea v0.24.2
    github.com/charmbracelet/bubbles v0.16.1
    github.com/charmbracelet/lipgloss v0.9.1
)
EOF

# ---------- source ----------
cat > main.go <<'GOEOF'
package main

import (
    "bufio"
    "context"
    "fmt"
    "os"
    "os/exec"
    "os/user"
    "regexp"
    "runtime"
    "strconv"
    "strings"
    "time"

    "github.com/charmbracelet/bubbles/help"
    "github.com/charmbracelet/bubbles/key"
    "github.com/charmbracelet/bubbles/progress"
    tea "github.com/charmbracelet/bubbletea"
    "github.com/charmbracelet/lipgloss"
)

type keys struct{ Quit, Help, Refresh key.Binding }

func (k keys) ShortHelp() []key.Binding  { return []key.Binding{k.Help, k.Refresh, k.Quit} }
func (k keys) FullHelp() [][]key.Binding { return [][]key.Binding{{k.Help, k.Refresh, k.Quit}} }

var keymap = keys{
    Quit:    key.NewBinding(key.WithKeys("q", "ctrl+c"), key.WithHelp("q/ctrl+c", "quit")),
    Help:    key.NewBinding(key.WithKeys("?"), key.WithHelp("?", "help")),
    Refresh: key.NewBinding(key.WithKeys("r"), key.WithHelp("r", "refresh now")),
}

type tickMsg time.Time
type refreshMsg struct{}

// tiny ring buffer for ASCII sparklines
type ring struct {
    data []float64
    max  int
}

func newRing(n int) *ring { return &ring{max: n} }
func (r *ring) push(v float64) {
    r.data = append(r.data, v)
    if len(r.data) > r.max {
        r.data = r.data[1:]
    }
}
func (r *ring) bars(width int, maxVal float64) string {
    blocks := []rune("▁▂▃▄▅▆▇█")
    if len(r.data) == 0 {
        return strings.Repeat(" ", width)
    }
    vals := make([]float64, width)
    for i := 0; i < width; i++ {
        idx := int(float64(i) / float64(width) * float64(len(r.data)-1))
        if idx < 0 {
            idx = 0
        }
        if idx >= len(r.data) {
            idx = len(r.data) - 1
        }
        vals[i] = r.data[idx]
    }
    if maxVal <= 0 {
        maxVal = 1
        for _, v := range r.data {
            if v > maxVal {
                maxVal = v
            }
        }
    }
    out := make([]rune, 0, width)
    for _, v := range vals {
        lvl := int((v / maxVal) * float64(len(blocks)-1))
        if lvl < 0 {
            lvl = 0
        }
        if lvl > len(blocks)-1 {
            lvl = len(blocks) - 1
        }
        out = append(out, blocks[lvl])
    }
    return string(out)
}

type model struct {
    host, usr                       string
    k                               keys
    h                               help.Model
    progCPU, progMem, progDisk      progress.Model
    cpuNow, memNow, diskNow         float64
    netNowInKBs, netNowOutKBs       float64
    cpuHist, netInHist, netOutHist  *ring
    ports, aiCLIs, disks, tailscale string
    uptime, load                    string
    title, section                  lipgloss.Style
    err                             error
}

func newModel() model {
    u, _ := user.Current()
    hn, _ := os.Hostname()
    m := model{
        host:       hn,
        usr:        u.Username,
        k:          keymap,
        h:          help.New(),
        progCPU:    progress.New(progress.WithDefaultGradient()),
        progMem:    progress.New(progress.WithDefaultGradient()),
        progDisk:   progress.New(progress.WithDefaultGradient()),
        cpuHist:    newRing(60),
        netInHist:  newRing(60),
        netOutHist: newRing(60),
        title:      lipgloss.NewStyle().Bold(true),
        section:    lipgloss.NewStyle().Foreground(lipgloss.Color("244")).Bold(true),
    }
    m.h.ShowAll = false
    return m
}

func (m model) Init() tea.Cmd { return tea.Batch(tick(), gather()) }
func tick() tea.Cmd {
    return tea.Tick(time.Second, func(t time.Time) tea.Msg { return tickMsg(t) })
}
func gather() tea.Cmd { return func() tea.Msg { return refreshMsg{} } }

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
    switch msg.(type) {
    case tea.KeyMsg:
        kk := msg.(tea.KeyMsg)
        switch {
        case key.Matches(kk, m.k.Quit):
            return m, tea.Quit
        case key.Matches(kk, m.k.Help):
            m.h.ShowAll = !m.h.ShowAll
        case key.Matches(kk, m.k.Refresh):
            return m, gather()
        }
    case tickMsg:
        return m, tea.Batch(gather(), tick())
    case refreshMsg:
        if err := m.sample(); err != nil {
            m.err = err
        }
    }
    return m, nil
}

func (m *model) sample() error {
    if b, err := os.ReadFile("/proc/stat"); err == nil {
        m.cpuNow = cpuPercentFromProcStat(string(b))
    }
    if b, err := os.ReadFile("/proc/meminfo"); err == nil {
        m.memNow = memPercentFromMeminfo(string(b))
    }
    if out, err := exec.Command("bash", "-lc",
        `df -P -x tmpfs -x devtmpfs -x squashfs / | awk 'NR==2{print $5}'`).Output(); err == nil {
        m.diskNow = parsePercent(string(out))
    }

    in, out := netBytes()
    m.netNowInKBs, m.netNowOutKBs = in, out

    m.cpuHist.push(m.cpuNow)
    m.netInHist.push(m.netNowInKBs)
    m.netOutHist.push(m.netNowOutKBs)

    m.uptime = readUptime()
    m.load = readLoad()

    if o := run(`ss -tulpnH 2>/dev/null | awk '{printf "%-4s %-22s %-28s %s\n",$1,$5,$6,$7}'`); o != "" {
        m.ports = firstLines(o, 12)
    } else {
        m.ports = firstLines(run(
            `LC_ALL=C lsof -nP -iTCP -sTCP:LISTEN -iUDP 2>/dev/null | head -n 12`), 12)
    }

    m.disks = diskTable()
    m.tailscale = tailscaleSummary()
    m.aiCLIs = strings.Join(checkAIWithVersions(), ", ")
    return nil
}

func (m model) View() string {
    title := m.title.Render(fmt.Sprintf(
        " %s@%s  (%s)  up %s  load %s ",
        m.usr, m.host, runtime.GOOS, m.uptime, m.load))
    head := lipgloss.NewStyle().Foreground(lipgloss.Color("6")).
        Render("Press ? for help • r to refresh")
    if m.err != nil {
        head += lipgloss.NewStyle().Foreground(lipgloss.Color("9")).
            Render("  ERR: " + m.err.Error())
    }

    row1 := fmt.Sprintf(
        "%s\nCPU  %s %5.1f%%   MEM  %s %5.1f%%   DISK %s %5.1f%%\n",
        m.section.Render("Resources"),
        m.progCPU.ViewAs(m.cpuNow/100), m.cpuNow,
        m.progMem.ViewAs(m.memNow/100), m.memNow,
        m.progDisk.ViewAs(m.diskNow/100), m.diskNow,
    )
    row2 := fmt.Sprintf(
        "%s\nCPU  %s\nNET↓ %s  %6.1f KB/s   NET↑ %s  %6.1f KB/s\n",
        m.section.Render("History (last ~60s)"),
        m.cpuHist.bars(40, 100),
        m.netInHist.bars(40, 0), m.netNowInKBs,
        m.netOutHist.bars(40, 0), m.netNowOutKBs,
    )

    left := m.section.Render("Ports & Services") + "\n" + code(m.ports)
    right := m.section.Render("AI CLIs detected") + "\n" + code(m.aiCLIs)
    side := sideBySide(left, right, 2)

    disks := m.section.Render("Disks (df -h)") + "\n" + code(m.disks)

    var ts string
    if m.tailscale != "" {
        ts = m.section.Render("Tailscale") + "\n" + code(m.tailscale) + "\n"
    }

    footer := m.h.View(m.k)
    return lipgloss.JoinVertical(lipgloss.Left, title, head, row1, row2, side, disks, ts, footer)
}

/* ---------- helpers ---------- */

func run(cmd string) string {
    ctx, cancel := context.WithTimeout(context.Background(), 1500*time.Millisecond)
    defer cancel()
    c := exec.CommandContext(ctx, "bash", "-lc", cmd)
    c.Env = append(os.Environ(), "LC_ALL=C")
    out, _ := c.Output()
    return strings.TrimRight(string(out), "\n")
}

func firstLines(s string, n int) string {
    lines := strings.Split(s, "\n")
    if n > 0 && len(lines) > n {
        lines = lines[:n]
    }
    return strings.Join(lines, "\n")
}

func parsePercent(s string) float64 {
    s = strings.TrimSpace(strings.TrimSuffix(s, "%"))
    v, _ := strconv.ParseFloat(s, 64)
    return v
}

func cpuPercentFromProcStat(s string) float64 {
    line := firstMatch(s, `^cpu\s+([0-9 ]+)`, true)
    if line == "" {
        return 0
    }
    f := strings.Fields(line)[1:]
    if len(f) < 8 {
        return 0
    }
    var n []float64
    for _, x := range f {
        v, _ := strconv.ParseFloat(x, 64)
        n = append(n, v)
    }
    idle := n[3] + n[4]
    total := 0.0
    for _, v := range n {
        total += v
    }
    if total <= 0 {
        return 0
    }
    return ((total - idle) / total) * 100
}

func memPercentFromMeminfo(s string) float64 {
    get := func(k string) float64 {
        rx := regexp.MustCompile(k + `:\s+([0-9]+)`)
        m := rx.FindStringSubmatch(s)
        if len(m) < 2 {
            return 0
        }
        v, _ := strconv.ParseFloat(m[1], 64)
        return v
    }
    t := get("MemTotal")
    a := get("MemAvailable")
    if t == 0 {
        return 0
    }
    return ((t - a) / t) * 100
}

var (
    prevRx, prevTx float64
    prevT          time.Time
)

func netBytes() (kbIn, kbOut float64) {
    b, err := os.ReadFile("/proc/net/dev")
    if err != nil {
        return 0, 0
    }
    s := bufio.NewScanner(strings.NewReader(string(b)))
    var rx, tx float64
    for s.Scan() {
        ln := s.Text()
        if !strings.Contains(ln, ":") {
            continue
        }
        parts := strings.Fields(strings.Split(ln, ":")[1])
        if len(parts) < 16 {
            continue
        }
        rxb, _ := strconv.ParseFloat(parts[0], 64)
        txb, _ := strconv.ParseFloat(parts[8], 64)
        rx += rxb
        tx += txb
    }
    now := time.Now()
    if !prevT.IsZero() {
        sec := now.Sub(prevT).Seconds()
        if sec > 0 {
            kbIn = (rx - prevRx) / 1024.0 / sec
            kbOut = (tx - prevTx) / 1024.0 / sec
        }
    }
    prevRx, prevTx, prevT = rx, tx, now
    if kbIn < 0 {
        kbIn = 0
    }
    if kbOut < 0 {
        kbOut = 0
    }
    return
}

func firstMatch(s, re string, multiline bool) string {
    rx := regexp.MustCompile(re)
    if multiline {
        for _, ln := range strings.Split(s, "\n") {
            if rx.MatchString(ln) {
                return ln
            }
        }
        return ""
    }
    return rx.FindString(s)
}

func code(s string) string {
    if strings.TrimSpace(s) == "" {
        return "—"
    }
    return lipgloss.NewStyle().Foreground(lipgloss.Color("10")).Render(s)
}

func padRight(s string, w int) string {
    r := []rune(s)
    if len(r) >= w {
        return s
    }
    return s + strings.Repeat(" ", w-len(r))
}

func sideBySide(left, right string, gap int) string {
    w := mn(80, termWidth()) / 2
    if w < 32 {
        w = 32
    }
    l := strings.Split(left, "\n")
    r := strings.Split(right, "\n")
    n := mx(len(l), len(r))
    out := make([]string, 0, n)
    for i := 0; i < n; i++ {
        ll, rl := "", ""
        if i < len(l) {
            ll = l[i]
        }
        if i < len(r) {
            rl = r[i]
        }
        out = append(out, padRight(ll, w)+strings.Repeat(" ", gap)+rl)
    }
    return strings.Join(out, "\n")
}

func termWidth() int {
    out, err := exec.Command("tput", "cols").Output()
    if err != nil {
        return 80
    }
    n, _ := strconv.Atoi(strings.TrimSpace(string(out)))
    if n <= 0 {
        return 80
    }
    return n
}

func mn(a, b int) int {
    if a < b {
        return a
    }
    return b
}
func mx(a, b int) int {
    if a > b {
        return a
    }
    return b
}

func readUptime() string {
    b, err := os.ReadFile("/proc/uptime")
    if err != nil {
        return "?"
    }
    f := strings.Fields(string(b))
    if len(f) == 0 {
        return "?"
    }
    sec, _ := strconv.ParseFloat(f[0], 64)
    d := time.Duration(sec) * time.Second
    days := int(d.Hours()) / 24
    hrs := int(d.Hours()) % 24
    mins := int(d.Minutes()) % 60
    if days > 0 {
        return fmt.Sprintf("%dd %dh %dm", days, hrs, mins)
    }
    return fmt.Sprintf("%dh %dm", hrs, mins)
}

func readLoad() string {
    b, err := os.ReadFile("/proc/loadavg")
    if err != nil {
        return "?"
    }
    f := strings.Fields(string(b))
    if len(f) < 3 {
        return "?"
    }
    return fmt.Sprintf("%s %s %s", f[0], f[1], f[2])
}

func diskTable() string {
    out := run(`df -h -T -x tmpfs -x devtmpfs -x squashfs | tail -n +2`)
    out = strings.TrimSpace(out)
    if out == "" {
        return "—"
    }
    lines := strings.Split(out, "\n")
    if len(lines) > 10 {
        lines = lines[:10]
    }
    header := fmt.Sprintf("%-16s %-8s %6s %6s %6s %5s  %s",
        "DEVICE", "FSTYPE", "SIZE", "USED", "AVAIL", "USE%", "MOUNT")
    rows := []string{header}
    for _, ln := range lines {
        f := strings.Fields(ln)
        if len(f) < 7 {
            continue
        }
        rows = append(rows, fmt.Sprintf("%-16s %-8s %6s %6s %6s %5s  %s",
            f[0], f[1], f[2], f[3], f[4], f[5], f[6]))
    }
    return strings.Join(rows, "\n")
}

func tailscaleSummary() string {
    if _, err := exec.LookPath("tailscale"); err != nil {
        return ""
    }
    self := run(`tailscale ip -4 2>/dev/null | head -1`)
    peers := run(`tailscale status 2>/dev/null | grep -cE '^[0-9]+\.'`)
    name := run(`tailscale status --self --json 2>/dev/null | grep -oP '"DNSName":\s*"\K[^"]+' | head -1`)
    if self == "" {
        return "installed but not joined"
    }
    return fmt.Sprintf("%s  IPv4: %s  peers: %s", name, self, peers)
}

func checkAIWithVersions() []string {
    cand := [][2]string{
        {"claude", "claude --version"},
        {"opencode", "opencode --version"},
        {"crush", "crush --version"},
        {"codex", "codex --version"},
        {"tmuxai", "tmuxai --version"},
        {"ollama", "ollama --version"},
        {"auggie", "auggie --version"},
        {"trae", "trae --version"},
        {"specify", "specify --version"},
        {"cursor", "cursor --version"},
        {"continue", "continue --version"},
        {"lmstudio", "lmstudio --version"},
        {"openai", "openai --version"},
        {"qwen", "qwen --version"},
        {"kimi", "kimi --version"},
        {"zai", "zai --version"},
        {"devin", "devin --version"},
    }
    var out []string
    for _, c := range cand {
        if _, err := exec.LookPath(c[0]); err == nil {
            ver := run(c[1] + " 2>/dev/null | head -n1")
            ver = strings.TrimSpace(ver)
            if ver == "" {
                out = append(out, c[0])
            } else {
                out = append(out, fmt.Sprintf("%s(%s)", c[0], ver))
            }
        }
    }
    if len(out) == 0 {
        return []string{"none"}
    }
    seen := map[string]bool{}
    var uniq []string
    for _, s := range out {
        if !seen[s] {
            seen[s] = true
            uniq = append(uniq, s)
        }
    }
    return uniq
}

func main() {
    if _, err := tea.NewProgram(newModel(), tea.WithAltScreen()).Run(); err != nil {
        fmt.Println("error:", err)
        os.Exit(1)
    }
}
GOEOF

# ---------- build ----------
echo "[*] Fetching Go dependencies (first time: ~30 s)…"
export GOPROXY=https://proxy.golang.org,direct
go mod tidy 2>&1 | sed 's/^/    /' || true

echo "[*] Building vpsview (first time: ~60 s)…"
CGO_ENABLED=0 go build -trimpath -ldflags="-s -w -buildid=" -o "$APP_NAME"

echo "[*] Installing binary to $INSTALL_BIN"
$SUDO install -m 0755 "$APP_NAME" "$INSTALL_BIN"

echo
echo "[✓] vpsview installed: $INSTALL_BIN"
echo "    Run:   vpsview"
echo "    Keys:  q quit · r refresh · ? help"
echo
echo "    Workspace kept at $WORKDIR for ~10s rebuilds. Safe to delete:"
echo "      rm -rf $WORKDIR"
