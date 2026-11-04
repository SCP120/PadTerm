#include "pt_session.h"
#include "pt_error.h"
#include "pt_quote.h"
#include <stdio.h>
#include <string.h>

int pt_session_key_valid(const char *key) {
    if (!key || strlen(key) != 36) return 0;
    for (int i = 0; i < 36; i++) {
        char c = key[i];
        if (i == 8 || i == 13 || i == 18 || i == 23) { if (c != '-') return 0; continue; }
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) return 0;
    }
    return 1;
}

#define PT_SCRIPT_PATH "PATH=\"$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin\"; export PATH\n"
#define PT_SCRIPT_DIRS "D=\"$HOME/.padterm\"; S=\"$D/sessions\"\n"

/* Fills P, the agent's transcript, when the record has none yet, and stores it as line 3. Needs K F A W P.
 * Codex: cwd is within the first 500 bytes of a rollout file (Codex 0.164, seen 2026-11-04); 4 KiB is the read. */
#define PT_SCRIPT_RESOLVE                                                                                    \
    "if [ -z \"$P\" ] || [ ! -f \"$P\" ]; then\n"                                                            \
    "  P=\n"                                                                                                 \
    "  if [ \"$A\" = claude ]; then\n"                                                                       \
    "    P=$(find \"$HOME/.claude/projects\" -maxdepth 2 -name \"$K.jsonl\" 2>/dev/null | head -n 1)\n"      \
    "  elif [ \"$A\" = codex ]; then\n"                                                                      \
    "    E=$(printf '%s' \"$W\" | sed 's/[\\\\\"]/\\\\&/g')\n" /* the rollout holds the directory as JSON text */     \
    "    P=$(find \"$HOME/.codex/sessions\" -name 'rollout-*.jsonl' -newer \"$F\" 2>/dev/null | sort |"      \
    " while read -r C; do\n"                                                                                 \
    "      grep -qsF \"$C\" \"$S\"/* \"$D/claimed\" && continue\n"                                           \
    "      head -c 4096 \"$C\" | grep -qF \"\\\"cwd\\\":\\\"$E\\\"\" || continue\n"                          \
    "      printf '%s\\n' \"$C\"; break\n"                                                                   \
    "    done)\n"                                                                                            \
    "  fi\n"                                                                                                 \
    /* Through a temp file outside $S: a reader must never see an empty record. */                         \
    "  if [ -n \"$P\" ]; then Q=\"$D/tmp.$$\"; printf '%s\\n%s\\n%s\\n' \"$A\" \"$W\" \"$P\" > \"$Q\";"           \
    " touch -r \"$F\" \"$Q\"; mv \"$Q\" \"$F\"; fi\n"                                                         \
    "fi\n"

/* The Codex session id is the end of the rollout file name. It reaches the agent's shell: only safe characters pass. */
#define PT_SCRIPT_CODEX_ID "I=${P##*/}; I=${I%.jsonl}; I=${I#rollout-?\?\?\?-?\?-?\?T?\?-?\?-?\?-}; case \"$I\" in *[!0-9A-Za-z-]*) I=;; esac\n"

/* Run script under sh: in zsh a glob with no match stops the command. The script holds newlines and is our own
 * text, so pt_shell_quote (which refuses newlines in user input) does not apply; user input is quoted inside it. */
static int wrap_sh(const char *script, char *out, size_t outlen) {
    static const char HEAD[] = "exec /bin/sh -c '";
    size_t n = sizeof HEAD - 1;
    if (outlen <= n) return PT_ERR_NOSPACE;
    memcpy(out, HEAD, n);
    for (const char *p = script; *p; p++) {
        const char *put = *p == '\'' ? "'\\''" : NULL;
        size_t m = put ? 4 : 1;
        if (n + m + 2 > outlen) return PT_ERR_NOSPACE;
        if (put) memcpy(out + n, put, m); else out[n] = *p;
        n += m;
    }
    out[n++] = '\'';
    out[n] = 0;
    return (int)n;
}

int pt_session_launch_command(pt_agent agent, const char *key, const char *dir, char *out, size_t outlen) {
    if ((agent != PT_AGENT_CLAUDE && agent != PT_AGENT_CODEX) || !pt_session_key_valid(key) || !out || outlen == 0)
        return PT_ERR_INVALID;
    char qdir[2048];
    int q = pt_quote_dir(dir ? dir : "", qdir, sizeof qdir);
    if (q < 0) return q;
    static const char BODY[] =
        "touch \"$D/seen/$K\"\n"
        "pt_tmux() { tmux -u -L padterm \"$@\"; }\n"
        "if ! pt_tmux has-session -t \"=pc-$K\" 2>/dev/null; then\n"
        "{ IFS= read -r A; IFS= read -r W; IFS= read -r P; } < \"$F\"\n"
        /* A Codex link rests on time and directory: a record already searched after its stop must not take a rollout
         * from a later run in that directory. A Claude link is an exact key match. */
        "if [ \"$A\" = claude ] || [ ! -e \"$D/searched/$K\" ]; then\n"
        PT_SCRIPT_RESOLVE
        "fi\n"
        "[ -n \"$P\" ] || touch \"$F\"\n" /* a new run: only rollouts from now on can belong to it */
        "rm -f \"$D/searched/$K\"\n"
        /* Each agent starts in its auto mode: fewer stops on a touch screen, but not a bypass;
         * both route risky actions to their automatic reviewer. codex --approve-for-me: seen in Codex 0.164. */
        "if [ \"$A\" = claude ]; then\n"
        "  if [ -n \"$P\" ]; then C=\"claude --resume $K --permission-mode auto\"; else C=\"claude --session-id $K --permission-mode auto\"; fi\n"
        "elif [ \"$A\" = codex ]; then\n"
        "  I=; if [ -n \"$P\" ]; then " PT_SCRIPT_CODEX_ID "  fi\n"
        "  if [ -n \"$I\" ]; then C=\"codex resume $I --approve-for-me\"; else C=\"codex --approve-for-me\"; fi\n"
        "else\n"
        "  echo \"padterm: bad record for session $K\"; exec \"$SHELL\" -l\n"
        "fi\n"
        /* An auto-mode agent must never start in another directory than the user chose. */
        "cd \"$W\" || { echo \"padterm: directory not found: $W\"; exec \"$SHELL\" -l; }\n"
        "T=tmux-256color; infocmp \"$T\" >/dev/null 2>&1 || T=xterm-256color\n"
        /* See pt_launch_command for the options. set-titles: the agent's session name reaches the terminal bar. */
        "pt_tmux start-server \\; set -g terminal-overrides ',xterm-256color:Tc' \\; set -g default-terminal \"$T\" \\; set -g status off "
        "\\; set -s escape-time 10 \\; set -g mouse on \\; set -g mode-keys emacs \\; set -g focus-events on "
        "\\; set -g set-titles on \\; set -g set-titles-string '#{pane_title}' "
        "\\; set-environment -g COLORTERM truecolor \\; set-environment -g CLAUDE_CODE_TMUX_TRUECOLOR 1 "
        "\\; new-session -d -s \"pc-$K\" \"$SHELL\" -lic \"$C || exec \\\"\\$SHELL\\\" -l\"\n"
        "fi\n"
        "exec tmux -u -L padterm attach -t \"=pc-$K\"\n";
    char script[8192];
    int n = snprintf(script, sizeof script,
        PT_SCRIPT_PATH
        "command -v tmux >/dev/null 2>&1 || { echo 'padterm: tmux not found'; exec \"$SHELL\" -l; }\n"
        PT_SCRIPT_DIRS
        "K=%s; F=\"$S/$K\"; mkdir -p \"$S\" \"$D/seen\"; chmod 700 \"$D\"\n"
        "if [ ! -f \"$F\" ]; then\n"
        "  W=$(cd %s 2>/dev/null && pwd -P) || { echo \"padterm: directory not found: \"%s; exec \"$SHELL\" -l; }\n"
        "  Q=\"$D/tmp.$$\"; printf '%%s\\n%%s\\n' %s \"$W\" > \"$Q\"; mv \"$Q\" \"$F\"\n"
        "fi\n",
        key, qdir, qdir, pt_agent_session(agent));
    if (n < 0 || (size_t)n + sizeof BODY > sizeof script) return PT_ERR_NOSPACE;
    memcpy(script + n, BODY, sizeof BODY);
    return wrap_sh(script, out, outlen);
}

int pt_session_list_command(char *out, size_t outlen) {
    /* 50: the row limit of the list (AC-SESSION-2 needs recent work, not all history). It follows the last attach, so
     * an old record comes back when the user opens it again; other records stay on the server.
     * 262144: 8 x the farthest title record from a transcript's end, 30 566 bytes in 22 titled transcripts
     * on a Mac, 2026-11-04 (the design doc has the method). */
    static const char SCRIPT[] =
        PT_SCRIPT_PATH
        PT_SCRIPT_DIRS
        "[ -d \"$S\" ] || exit 0\n"
        "R=\"$D/records\"; X=\"$HOME/.codex/session_index.jsonl\"; mkdir -p \"$R\" \"$D/searched\"\n"
        "L=$(tmux -u -L padterm list-sessions -F '#{session_name}' 2>/dev/null)\n"
        "mt() { stat -c %Y \"$1\" 2>/dev/null || stat -f %m \"$1\" 2>/dev/null; }\n"
        "ls -t \"$D/seen\" 2>/dev/null | head -n 50 | while IFS= read -r K; do\n"
        "F=\"$S/$K\"; O=\"$R/$K\"; A=; W=; P=; U=0\n"
        "[ -f \"$F\" ] || continue\n"
        "case \"\n$L\n\" in *\"\npc-$K\n\"*) U=1;; esac\n"
        "{ IFS= read -r A; IFS= read -r W; IFS= read -r P; } < \"$F\"\n"
        /* A running session can make a transcript at any time; a stopped one made its last before it stopped, so one
         * search after the stop is enough (BR-SESSION-2). */
        "if [ \"$U\" = 1 ] || [ ! -e \"$D/searched/$K\" ]; then\n"
        PT_SCRIPT_RESOLVE
        "fi\n"
        "[ \"$U\" = 1 ] || : > \"$D/searched/$K\"\n"
        "if [ ! -f \"$O\" ] || [ \"$P\" -nt \"$O\" ] || [ \"$D/seen/$K\" -nt \"$O\" ] || { [ \"$A\" = codex ] && [ \"$X\" -nt \"$O\" ]; }; then\n"
        "  M=$(mt \"$D/seen/$K\"); [ -n \"$M\" ] || M=$(mt \"$F\")\n"
        "  if [ -n \"$P\" ]; then N=$(mt \"$P\"); [ \"${N:-0}\" -gt \"${M:-0}\" ] && M=$N; fi\n"
        "  Y=\n"
        "  if [ -n \"$P\" ] && [ \"$A\" = claude ]; then\n"
        "    Z=$(tail -c 262144 \"$P\" | grep -E '\"type\":\"(custom-title|ai-title)\"')\n"
        "    Y=$(printf '%s\\n' \"$Z\" | grep '\"type\":\"custom-title\"' | tail -n 1)\n"
        "    [ -n \"$Y\" ] || Y=$(printf '%s\\n' \"$Z\" | tail -n 1)\n"
        "  elif [ -n \"$P\" ] && [ -f \"$X\" ]; then\n"
        "    " PT_SCRIPT_CODEX_ID
        "    [ -n \"$I\" ] && Y=$(grep -F \"\\\"id\\\":\\\"$I\\\"\" \"$X\" | tail -n 1)\n"
        "  fi\n"
        "  { printf 'S\\t%s\\t%s\\t%s\\t%s\\n' \"$K\" \"$A\" \"$M\" \"$W\"; [ -z \"$Y\" ] || printf 'T\\t%s\\t%s\\n' \"$K\" \"$Y\"; } > \"$O\"\n"
        "fi\n"
        "cat \"$O\"\n"
        "[ \"$U\" = 0 ] || printf 'R\\t%s\\n' \"$K\"\n"
        "done\n";
    return wrap_sh(SCRIPT, out, outlen);
}

int pt_session_remove_command(const char *key, char *out, size_t outlen) {
    if (!pt_session_key_valid(key) || !out || outlen == 0) return PT_ERR_INVALID;
    char script[1024];
    int n = snprintf(script, sizeof script,
        PT_SCRIPT_PATH PT_SCRIPT_DIRS
        "K=%s\n"
        "tmux -u -L padterm kill-session -t \"=pc-$K\" 2>/dev/null\n"
        "[ ! -f \"$S/$K\" ] || sed -n 3p \"$S/$K\" >> \"$D/claimed\"\n"
        "rm -f \"$S/$K\" \"$D/seen/$K\" \"$D/records/$K\" \"$D/searched/$K\"\n", key);
    if (n < 0 || (size_t)n >= sizeof script) return PT_ERR_NOSPACE;
    return wrap_sh(script, out, outlen);
}

/* Length of a leading "<symbol> ": one non-ASCII character (✳, a Braille spinner frame) and a space. */
static size_t symbol_prefix(const char *t) {
    const unsigned char *u = (const unsigned char *)t;
    size_t n = u[0] >= 0xF0 ? 4 : u[0] >= 0xE0 ? 3 : u[0] >= 0xC0 ? 2 : 0;
    if (!n) return 0;
    for (size_t i = 1; i < n; i++) if ((u[i] & 0xC0) != 0x80) return 0;
    return u[n] == ' ' ? n + 1 : 0;
}

int pt_session_clean_title(pt_agent agent, const char *title, char *out, size_t outlen) {
    if (!title || !out || outlen == 0) return 0;
    size_t skip = symbol_prefix(title), len;
    const char *name = title + skip;
    if (agent == PT_AGENT_CLAUDE) {
        if (!skip || strcmp(name, "Claude Code") == 0) return 0; /* tmux first shows the host name, with no symbol */
        len = strlen(name);
    } else if (agent == PT_AGENT_CODEX) {
        const char *bar = NULL;
        for (const char *p = name; (p = strstr(p, " | ")) != NULL; p += 3) bar = p; /* the last one: a name can hold " | " */
        if (!bar) return 0;
        len = (size_t)(bar - name);
    } else {
        return 0;
    }
    if (len == 0 || len >= outlen) return 0;
    memcpy(out, name, len);
    out[len] = 0;
    return 1;
}
