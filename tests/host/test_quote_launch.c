#include "pt_test.h"
#include "../../core/pt_error.h"
#include "../../core/pt_quote.h"
#include "../../core/pt_launch.h"
#include "../../core/pt_backoff.h"

PT_TEST(quote_plain_and_single_quote, "BR-LAUNCH-2") {
    char b[64];
    CHECK_INT(pt_shell_quote("abc", b, sizeof b), 5); CHECK_STR(b, "'abc'");
    CHECK(pt_shell_quote("it's", b, sizeof b) > 0); CHECK_STR(b, "'it'\\''s'");
    CHECK(pt_shell_quote("", b, sizeof b) > 0); CHECK_STR(b, "''");
    CHECK(pt_shell_quote("$HOME `x` \"q\"", b, sizeof b) > 0); CHECK_STR(b, "'$HOME `x` \"q\"'");
}

PT_TEST(quote_refuses_control_chars, "EF-LAUNCH-2") {
    char b[64];
    CHECK_INT(pt_shell_quote("a\nb", b, sizeof b), PT_ERR_INVALID);
    CHECK_INT(pt_shell_quote("a\rb", b, sizeof b), PT_ERR_INVALID);
    CHECK_INT(pt_shell_quote("a\x7f", b, sizeof b), PT_ERR_INVALID);
    CHECK_INT(pt_quote_dir("~/x\ty", b, sizeof b), PT_ERR_INVALID);
}

PT_TEST(quote_no_space, "BR-LAUNCH-2") {
    char b[5];
    CHECK_INT(pt_shell_quote("abc", b, sizeof b), PT_ERR_NOSPACE);  /* needs 6 with NUL */
    CHECK_INT(pt_shell_quote("ab", b, sizeof b), 4);
}

PT_TEST(quote_dir_home_forms, "BR-LAUNCH-2") {
    char b[128];
    CHECK(pt_quote_dir("", b, sizeof b) > 0); CHECK_STR(b, "\"$HOME\"");
    CHECK(pt_quote_dir("~", b, sizeof b) > 0); CHECK_STR(b, "\"$HOME\"");
    CHECK(pt_quote_dir("~/", b, sizeof b) > 0); CHECK_STR(b, "\"$HOME\"");
    CHECK(pt_quote_dir("~/src/app", b, sizeof b) > 0); CHECK_STR(b, "\"$HOME\"/'src/app'");
    CHECK(pt_quote_dir("/tmp/x y", b, sizeof b) > 0); CHECK_STR(b, "'/tmp/x y'");
    CHECK(pt_quote_dir("rel/dir", b, sizeof b) > 0); CHECK_STR(b, "'rel/dir'");
    CHECK_INT(pt_quote_dir("~bob/x", b, sizeof b), PT_ERR_INVALID);
}

/* Golden vector: the exact command of docs/architecture/designs/padterm.md "Remote command". */
static const char *GOLDEN_CLAUDE =
    "PATH=\"$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin\"; export PATH; "
    "command -v tmux >/dev/null 2>&1 || { echo 'padterm: tmux not found'; exec \"$SHELL\" -l; }; "
    "pt_tmux() { tmux -u -L padterm \"$@\"; }; "
    "pt_tmux has-session -t '=claude' 2>/dev/null || { PT_T=tmux-256color; "
    "infocmp \"$PT_T\" >/dev/null 2>&1 || PT_T=xterm-256color; "
    "pt_tmux start-server \\; set -g terminal-overrides ',xterm-256color:Tc' \\; set -g default-terminal \"$PT_T\" \\; set -g status off "
    "\\; set -s escape-time 10 \\; set -g mouse on \\; set -g mode-keys emacs \\; set -g focus-events on \\; set-environment -g COLORTERM truecolor \\; set-environment -g CLAUDE_CODE_TMUX_TRUECOLOR 1 "
    "\\; new-session -d -s claude -c \"$HOME\"/'src/app' \"$SHELL\" -lic 'claude --permission-mode auto; exec \"$SHELL\" -l'; }; "
    "exec tmux -u -L padterm attach -t '=claude'";

PT_TEST(launch_claude_golden, "AC-LAUNCH-1 AC-LAUNCH-2 AC-LAUNCH-3 BR-LAUNCH-1 BR-LAUNCH-3 EF-LAUNCH-1") {
    char b[2048];
    int n = pt_launch_command(PT_AGENT_CLAUDE, "~/src/app", b, sizeof b);
    CHECK(n > 0);
    CHECK_STR(b, GOLDEN_CLAUDE);
    CHECK_INT(n, (int)strlen(GOLDEN_CLAUDE));
}

PT_TEST(launch_codex_and_shell, "AC-LAUNCH-1 AC-LAUNCH-2") {
    char b[2048];
    CHECK(pt_launch_command(PT_AGENT_CODEX, "/srv/x", b, sizeof b) > 0);
    CHECK(strstr(b, "new-session -d -s codex -c '/srv/x' \"$SHELL\" -lic 'codex --approve-for-me; exec \"$SHELL\" -l'; }; "
                    "exec tmux -u -L padterm attach -t '=codex'") != NULL);
    CHECK(pt_launch_command(PT_AGENT_SHELL, "", b, sizeof b) > 0);
    CHECK(strstr(b, "new-session -d -s shell -c \"$HOME\"; }; exec tmux -u -L padterm attach -t '=shell'") != NULL);
    CHECK(strstr(b, "-lic") == NULL);
}

PT_TEST(launch_session_names, "AC-LAUNCH-1") {
    CHECK_STR(pt_agent_session(PT_AGENT_CLAUDE), "claude");
    CHECK_STR(pt_agent_session(PT_AGENT_CODEX), "codex");
    CHECK_STR(pt_agent_session(PT_AGENT_SHELL), "shell");
    CHECK(pt_agent_session((pt_agent)7) == NULL);
}

PT_TEST(launch_refuses_bad_input, "EF-LAUNCH-2") {
    char b[2048];
    CHECK_INT(pt_launch_command(PT_AGENT_CLAUDE, "~/x\ny", b, sizeof b), PT_ERR_INVALID);
    CHECK_INT(pt_launch_command((pt_agent)9, "~", b, sizeof b), PT_ERR_INVALID);
    CHECK_INT(pt_launch_command(PT_AGENT_CLAUDE, "~", b, 40), PT_ERR_NOSPACE);
}

PT_TEST(backoff_sequence, "AC-RECONNECT-2") {
    pt_backoff bo; pt_backoff_reset(&bo);
    static const int expected[] = {1000, 2000, 4000, 8000, 16000, 30000, 30000};
    for (size_t i = 0; i < sizeof expected / sizeof *expected; i++) CHECK_INT(pt_backoff_next(&bo), expected[i]);
    pt_backoff_reset(&bo);
    CHECK_INT(pt_backoff_next(&bo), 1000);
}

PT_TEST(reconnect_only_after_lost_link, "BR-RECONNECT-1 AC-RECONNECT-2") {
    CHECK_INT(pt_should_reconnect(PT_OK), 0);              /* user closed */
    CHECK_INT(pt_should_reconnect(PT_ERR_HOSTKEY_MISMATCH), 0);
    CHECK_INT(pt_should_reconnect(PT_ERR_AUTH), 0);
    CHECK_INT(pt_should_reconnect(PT_ERR_KEY_INVALID), 0);
    CHECK_INT(pt_should_reconnect(PT_ERR_INVALID), 0);
    CHECK_INT(pt_should_reconnect(PT_ERR_IO), 1);
    CHECK_INT(pt_should_reconnect(PT_ERR_TIMEOUT), 1);
    CHECK_INT(pt_should_reconnect(PT_ERR_CONNECT), 1);
    CHECK_INT(pt_should_reconnect(PT_ERR_CLOSED), 0);  /* session ended on the server */
}

PT_TEST(status_text, "EF-CONNECT-1 EF-CONNECT-2 EF-CONNECT-3") {
    CHECK_STR(pt_status_text(PT_ERR_AUTH), "authentication failed");
    CHECK_STR(pt_status_text(PT_ERR_TIMEOUT), "connection timed out");
    CHECK_STR(pt_status_text(PT_ERR_KEY_INVALID), "invalid key");
    CHECK_STR(pt_status_text(PT_ERR_HOSTKEY_MISMATCH), "host key does not match the pinned key");
    CHECK(pt_status_text(12345) != NULL);
}

PT_TEST(launch_hash_in_directory_is_literal, "BR-LAUNCH-2") {
    char b[2048];
    CHECK(pt_launch_command(PT_AGENT_SHELL, "~/C#Sharp/x##y", b, sizeof b) > 0);
    /* tmux expands #-formats in -c; ## is a literal # (tmux(1) FORMATS) */
    CHECK(strstr(b, "-c \"$HOME\"/'C##Sharp/x####y'") != NULL);
}
