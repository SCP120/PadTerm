#include "pt_launch.h"
#include "pt_error.h"
#include "pt_quote.h"
#include <stdarg.h>
#include <stdio.h>

const char *pt_agent_session(pt_agent agent) {
    switch (agent) {
    case PT_AGENT_CLAUDE: return "claude";
    case PT_AGENT_CODEX: return "codex";
    case PT_AGENT_SHELL: return "shell";
    default: return NULL;
    }
}

typedef struct { char *buf; size_t cap, len; int full; } sbuf;

static void put(sbuf *b, const char *fmt, ...) {
    if (b->full) return;
    va_list ap; va_start(ap, fmt);
    int n = vsnprintf(b->buf + b->len, b->cap - b->len, fmt, ap);
    va_end(ap);
    if (n < 0 || (size_t)n >= b->cap - b->len) { b->full = 1; return; }
    b->len += (size_t)n;
}

int pt_launch_command(pt_agent agent, const char *dir, char *out, size_t outlen) {
    const char *s = pt_agent_session(agent);
    if (!s || !out || outlen == 0) return PT_ERR_INVALID;
    /* tmux expands formats in the -c value ("#S", "##"): double every '#' so the path stays literal. */
    char hdir[1024];
    size_t n = 0;
    for (const char *p = dir ? dir : ""; *p; p++) {
        if (n + 3 > sizeof hdir) return PT_ERR_NOSPACE;
        if (*p == '#') hdir[n++] = '#';
        hdir[n++] = *p;
    }
    hdir[n] = 0;
    char qdir[2048];
    int q = pt_quote_dir(hdir, qdir, sizeof qdir);
    if (q < 0) return q;
    sbuf b = {out, outlen, 0, 0};
    put(&b, "PATH=\"$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin\"; export PATH; ");
    put(&b, "command -v tmux >/dev/null 2>&1 || { echo 'padterm: tmux not found'; exec \"$SHELL\" -l; }; ");
    put(&b, "pt_tmux() { tmux -u -L padterm \"$@\"; }; ");
    /* tmux shows italics as reverse when default-terminal starts with "screen" (tty.c, tty_set_italics).
     * CLAUDE_CODE_TMUX_TRUECOLOR: inside tmux Claude Code otherwise sends 256 colours, and its orange becomes pale pink.
     * mode-keys emacs: with EDITOR=vi tmux picks vi keys, where Esc does not leave scrollback (seen on the iPad). */
    put(&b, "pt_tmux has-session -t '=%s' 2>/dev/null || { PT_T=tmux-256color; "
            "infocmp \"$PT_T\" >/dev/null 2>&1 || PT_T=xterm-256color; ", s);
    put(&b, "pt_tmux start-server \\; set -g terminal-overrides ',xterm-256color:Tc' \\; set -g default-terminal \"$PT_T\" \\; set -g status off "
            "\\; set -s escape-time 10 \\; set -g mouse on \\; set -g mode-keys emacs \\; set -g focus-events on \\; set-environment -g COLORTERM truecolor \\; set-environment -g CLAUDE_CODE_TMUX_TRUECOLOR 1 "
            "\\; new-session -d -s %s -c %s", s, qdir);
    /* The agent runs under an interactive login shell, so the user's PATH setup applies; after the agent
     * exits, a login shell stays in the project directory. */
    /* Each agent starts in its auto mode (owner's choice): fewer stops on a touch screen, but not a bypass;
     * both route risky actions to their automatic reviewer. codex --approve-for-me: seen in Codex 0.164. */
    if (agent == PT_AGENT_CLAUDE) put(&b, " \"$SHELL\" -lic 'claude --permission-mode auto; exec \"$SHELL\" -l'");
    if (agent == PT_AGENT_CODEX) put(&b, " \"$SHELL\" -lic 'codex --approve-for-me; exec \"$SHELL\" -l'");
    put(&b, "; }; exec tmux -u -L padterm attach -t '=%s'", s);
    if (b.full) return PT_ERR_NOSPACE;
    return (int)b.len;
}
