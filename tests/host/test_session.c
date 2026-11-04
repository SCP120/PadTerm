#include "pt_test.h"
#include "../../core/pt_error.h"
#include "../../core/pt_session.h"
#include "../../core/pt_term.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define KEY_A "11111111-1111-4111-8111-111111111111"
#define KEY_B "22222222-2222-4222-8222-222222222222"
#define KEY_C "33333333-3333-4333-8333-333333333333"
#define CODEX_ID "0aaaaaaa-0000-7000-8000-000000000001"

PT_TEST(session_key_valid, "BR-SESSION-3") {
    CHECK_INT(pt_session_key_valid(KEY_A), 1);
    CHECK_INT(pt_session_key_valid("ABCDEF00-1111-4111-8111-111111111111"), 1);
    CHECK_INT(pt_session_key_valid(NULL), 0);
    CHECK_INT(pt_session_key_valid("11111111-1111-4111-8111-11111111111"), 0);
    CHECK_INT(pt_session_key_valid("11111111-1111-4111-8111-11111111111;"), 0);
    CHECK_INT(pt_session_key_valid("../../../../etc/passwd-aaaaaaaaaaaaa"), 0);
}

/* Frozen titles: Claude on the mini and Codex 0.164 on the owner's Mac, 2026-11-03. */
PT_TEST(session_clean_title_golden, "AC-SESSION-4") {
    char b[128];
    CHECK_INT(pt_session_clean_title(PT_AGENT_CLAUDE, "\xE2\x9C\xB3 Note-taking web app", b, sizeof b), 1);
    CHECK_STR(b, "Note-taking web app");
    CHECK_INT(pt_session_clean_title(PT_AGENT_CLAUDE, "\xE2\xA0\x82 Note-taking web app", b, sizeof b), 1);
    CHECK_STR(b, "Note-taking web app");
    CHECK_INT(pt_session_clean_title(PT_AGENT_CLAUDE, "\xE2\x9C\xB3 Claude Code", b, sizeof b), 0);
    CHECK_INT(pt_session_clean_title(PT_AGENT_CLAUDE, "my-mac.local", b, sizeof b), 0);
    CHECK_INT(pt_session_clean_title(PT_AGENT_CODEX, "Reply padterm probe | dir", b, sizeof b), 1);
    CHECK_STR(b, "Reply padterm probe");
    CHECK_INT(pt_session_clean_title(PT_AGENT_CODEX, "\xE2\xA0\x8B Reply padterm probe | dir", b, sizeof b), 1);
    CHECK_STR(b, "Reply padterm probe");
    CHECK_INT(pt_session_clean_title(PT_AGENT_CODEX, "a | b | dir", b, sizeof b), 1);
    CHECK_STR(b, "a | b");
    CHECK_INT(pt_session_clean_title(PT_AGENT_CODEX, "dir", b, sizeof b), 0);
    CHECK_INT(pt_session_clean_title(PT_AGENT_SHELL, "\xE2\x9C\xB3 x", b, sizeof b), 0);
    CHECK_INT(pt_session_clean_title(PT_AGENT_CLAUDE, "\xE2\x9C\xB3 long name", b, 4), 0);
}

PT_TEST(term_title_taken_once, "AC-SESSION-4") {
    pt_term *t = pt_term_new(5, 20, NULL, NULL);
    CHECK(pt_term_take_title(t) == NULL);
    pt_term_feed(t, "\033]2;first\007", 10);
    CHECK_STR(pt_term_take_title(t), "first");
    CHECK(pt_term_take_title(t) == NULL);
    pt_term_feed(t, "\033]0;sec", 7); /* a title that arrives in two reads */
    CHECK(pt_term_take_title(t) == NULL);
    pt_term_feed(t, "ond\007", 4);
    CHECK_STR(pt_term_take_title(t), "second");
    pt_term_free(t);
}

PT_TEST(session_commands_refuse_bad_input, "BR-SESSION-3 EF-LAUNCH-2") {
    char b[16384];
    CHECK_INT(pt_session_launch_command(PT_AGENT_CLAUDE, "x; rm -rf ~", "~", b, sizeof b), PT_ERR_INVALID);
    CHECK_INT(pt_session_launch_command(PT_AGENT_SHELL, KEY_A, "~", b, sizeof b), PT_ERR_INVALID);
    CHECK_INT(pt_session_launch_command(PT_AGENT_CLAUDE, KEY_A, "~/x\ny", b, sizeof b), PT_ERR_INVALID);
    CHECK_INT(pt_session_launch_command(PT_AGENT_CLAUDE, KEY_A, "~", b, 40), PT_ERR_NOSPACE);
    CHECK_INT(pt_session_remove_command("$(id)", b, sizeof b), PT_ERR_INVALID);
    CHECK_INT(pt_session_list_command(b, 40), PT_ERR_NOSPACE);
}

/* ---- the real scripts, under the two shells, in a private HOME with stand-in tmux/claude/codex ---- */

typedef struct { char home[256], bin[256], log[256]; } box;

static void sh(const char *fmt, const char *a, const char *b, const char *c) {
    char cmd[4096];
    snprintf(cmd, sizeof cmd, fmt, a, b, c);
    if (system(cmd) != 0) pt_test_fail(__FILE__, __LINE__, "setup: %s", cmd);
}

static void box_cleanup(void *p) { box *x = p; sh("rm -rf %.200s %.0s%.0s", x->home, "", ""); free(x); }

/* tmux stand-in: has-session fails unless the session is in $HOME/live; attach records its args; new-session
 * records the working directory and the agent command. */
static box *make_box(void) {
    box *x = calloc(1, sizeof *x);
    char tpl[] = "/tmp/ptsXXXXXX";
    snprintf(x->home, sizeof x->home, "%s", mkdtemp(tpl));
    snprintf(x->bin, sizeof x->bin, "%s/bin", x->home);
    snprintf(x->log, sizeof x->log, "%s/log", x->home);
    pt_test_defer(box_cleanup, x);
    sh("mkdir -p %s %s/.claude/projects/-work-a %s/.codex/sessions/2026/11/04", x->bin, x->home, x->home);
    char f[512];
    snprintf(f, sizeof f, "%s/tmux", x->bin);
    FILE *t = fopen(f, "w");
    fputs("#!/bin/sh\n"
          "case \" $* \" in\n"
          "*\" has-session \"*) for a; do l=$a; done; grep -qx \"${l#=}\" \"$HOME/live\" 2>/dev/null; exit $?;;\n"
          "*\" list-sessions \"*) cat \"$HOME/live\" 2>/dev/null; exit 0;;\n"
          "*\" kill-session \"*) echo \"kill $*\" >> \"$HOME/log\"; exit 0;;\n"
          "*\" attach \"*) echo \"attach $*\" >> \"$HOME/log\"; exit 0;;\n"
          "*\" new-session \"*) echo \"new pwd=$PWD\" >> \"$HOME/log\"; for a; do l=$a; done; echo \"cmd=$l\" >> \"$HOME/log\"; exit 0;;\n"
          "esac\nexit 0\n", t);
    fclose(t);
    chmod(f, 0755);
    return x;
}

/* Run a command the app built, in the box. `shell` plays the login shell that sshd starts; zsh is the hard case. */
static char *run(box *x, const char *command, const char *shell) {
    static char buf[16384];
    char path[256];
    snprintf(path, sizeof path, "%s/cmd", x->home);
    FILE *f = fopen(path, "w");
    /* The script body must run under dash too: /bin/sh is dash on Debian and Ubuntu servers. */
    static const char SH[] = "exec /bin/sh -c ";
    if (strstr(shell, "dash") && strncmp(command, SH, sizeof SH - 1) == 0) fprintf(f, "exec /bin/dash -c %s", command + sizeof SH - 1);
    else fputs(command, f);
    fclose(f);
    char cmd[1024];
    /* The stand-in tmux comes first in PATH; the script appends its own folders after it. */
    snprintf(cmd, sizeof cmd, "HOME=%s SHELL=/usr/bin/true PATH=%s:/usr/bin:/bin %s %s 2>&1 </dev/null", x->home, x->bin, shell, path);
    FILE *p = popen(cmd, "r");
    size_t n = fread(buf, 1, sizeof buf - 1, p);
    buf[n] = 0;
    pclose(p);
    return buf;
}

static char *slurp(const char *path) {
    static char buf[8192];
    FILE *f = fopen(path, "r");
    if (!f) return (char *)"";
    size_t n = fread(buf, 1, sizeof buf - 1, f);
    buf[n] = 0;
    fclose(f);
    return buf;
}



static void list_fixture_test(const char *shell) {
    box *x = make_box();
    char b[16384], p[512], cmd[1024];
    /* Start a Claude and a Codex session: no transcript yet, so new-session uses --session-id and plain codex. */
    sh("mkdir -p %s/work/a\\ b%.0s%.0s", x->home, "", "");
    char dir[400];
    snprintf(dir, sizeof dir, "%s/work/a b", x->home);
    CHECK(pt_session_launch_command(PT_AGENT_CLAUDE, KEY_A, dir, b, sizeof b) > 0);
    CHECK_STR(run(x, b, shell), "");
    char *log = slurp(x->log);
    CHECK(strstr(log, "--session-id " KEY_A " --permission-mode auto") != NULL);
    CHECK(strstr(log, "/work/a b\n") != NULL);
    CHECK(strstr(log, "attach -u -L padterm attach -t =pc-" KEY_A "\n") != NULL || strstr(log, "attach -t =pc-" KEY_A) != NULL);
    unlink(x->log);
    CHECK(pt_session_launch_command(PT_AGENT_CODEX, KEY_B, dir, b, sizeof b) > 0);
    CHECK_STR(run(x, b, shell), "");
    CHECK(strstr(slurp(x->log), "cmd=codex --approve-for-me || exec") != NULL);
    unlink(x->log);
    /* Listing before any message: rows with no name. */
    CHECK(pt_session_list_command(b, sizeof b) > 0);
    char *o = run(x, b, shell);
    CHECK(strstr(o, "S\t" KEY_A "\tclaude\t") != NULL);
    CHECK(strstr(o, "S\t" KEY_B "\tcodex\t") != NULL);
    CHECK(strstr(o, "T\t") == NULL);
    CHECK(strstr(o, "R\t") == NULL);
    sleep(1); /* file times have 1 s steps: the agent files below must be newer than the records */
    /* Agents write their files. The real Codex record holds much more before and after cwd. */
    snprintf(p, sizeof p, "%s/.claude/projects/-work-a/" KEY_A ".jsonl", x->home);
    FILE *f = fopen(p, "w");
    fputs("{\"type\":\"user\",\"message\":\"mentions \\\"type\\\":\\\"ai-title\\\" in text\"}\n"
          "{\"type\":\"ai-title\",\"aiTitle\":\"Old name\",\"sessionId\":\"" KEY_A "\"}\n"
          "{\"type\":\"ai-title\",\"aiTitle\":\"Note app\",\"sessionId\":\"" KEY_A "\"}\n", f);
    fclose(f);
    snprintf(p, sizeof p, "%s/.codex/sessions/2026/11/04/rollout-2026-11-04T00-12-06-" CODEX_ID ".jsonl", x->home);
    char real[512];
    snprintf(cmd, sizeof cmd, "cd '%s' && pwd -P", dir);
    FILE *pw = popen(cmd, "r");
    real[fread(real, 1, sizeof real - 1, pw)] = 0;
    pclose(pw);
    real[strcspn(real, "\n")] = 0;
    f = fopen(p, "w");
    fprintf(f, "{\"timestamp\":\"t\",\"type\":\"session_meta\",\"payload\":{\"id\":\"" CODEX_ID "\",\"cwd\":\"%s\"}}\n", real);
    fclose(f);
    snprintf(p, sizeof p, "%s/.codex/session_index.jsonl", x->home);
    f = fopen(p, "w");
    fputs("{\"id\":\"other\",\"thread_name\":\"Other\",\"updated_at\":\"t\"}\n"
          "{\"id\":\"" CODEX_ID "\",\"thread_name\":\"Reply probe\",\"updated_at\":\"t\"}\n", f);
    fclose(f);
    snprintf(p, sizeof p, "%s/live", x->home);
    f = fopen(p, "w");
    fputs("pc-" KEY_A "\npc-" KEY_B "\nclaude\n", f);
    fclose(f);
    sleep(1);
    CHECK(pt_session_list_command(b, sizeof b) > 0);
    o = run(x, b, shell);
    CHECK(strstr(o, "T\t" KEY_A "\t{\"type\":\"ai-title\",\"aiTitle\":\"Note app\"") != NULL); /* the last one */
    CHECK(strstr(o, "T\t" KEY_B "\t{\"id\":\"" CODEX_ID "\",\"thread_name\":\"Reply probe\"") != NULL);
    CHECK(strstr(o, "R\t" KEY_A "\n") != NULL);
    CHECK(strstr(o, "R\t" KEY_B "\n") != NULL);
    snprintf(p, sizeof p, "%s/live", x->home);
    f = fopen(p, "w");
    fputs("pc-" KEY_A "\nclaude\n", f);
    fclose(f);
    o = run(x, b, shell);
    CHECK(strstr(o, "R\t" KEY_B "\n") == NULL); /* no longer live */
    CHECK(strstr(o, "T\t" KEY_B "\t") != NULL); /* its name stays */
    /* A rename: custom-title wins over a later ai-title (AC-SESSION-3, AC-SESSION-4). */
    sleep(1);
    snprintf(p, sizeof p, "%s/.claude/projects/-work-a/" KEY_A ".jsonl", x->home);
    f = fopen(p, "a");
    fputs("{\"type\":\"custom-title\",\"customTitle\":\"My name\",\"sessionId\":\"" KEY_A "\"}\n"
          "{\"type\":\"ai-title\",\"aiTitle\":\"Later ai\",\"sessionId\":\"" KEY_A "\"}\n", f);
    fclose(f);
    o = run(x, b, shell);
    CHECK(strstr(o, "T\t" KEY_A "\t{\"type\":\"custom-title\",\"customTitle\":\"My name\"") != NULL);
    /* Continue: the agents' resume commands, in the recorded directory, also when the profile's directory changed. */
    snprintf(p, sizeof p, "%s/live", x->home);
    unlink(p);
    unlink(x->log);
    CHECK(pt_session_launch_command(PT_AGENT_CLAUDE, KEY_A, "~/elsewhere", b, sizeof b) > 0);
    CHECK_STR(run(x, b, shell), "");
    log = slurp(x->log);
    CHECK(strstr(log, "--resume " KEY_A " --permission-mode auto") != NULL);
    CHECK(strstr(log, "/work/a b\n") != NULL);
    unlink(x->log);
    CHECK(pt_session_launch_command(PT_AGENT_CODEX, KEY_B, dir, b, sizeof b) > 0);
    CHECK_STR(run(x, b, shell), "");
    CHECK(strstr(slurp(x->log), "cmd=codex resume " CODEX_ID " --approve-for-me || exec") != NULL);
    /* A second Codex session in the same directory does not take the file of the first (EF-SESSION-2). */
    unlink(x->log);
    sleep(1);
    CHECK(pt_session_launch_command(PT_AGENT_CODEX, KEY_C, dir, b, sizeof b) > 0);
    CHECK_STR(run(x, b, shell), "");
    CHECK(strstr(slurp(x->log), "cmd=codex --approve-for-me || exec") != NULL);
    /* After a removed session, a new Codex session in the same directory must not take its file. */
    snprintf(p, sizeof p, "%s/live", x->home);
    f = fopen(p, "w");
    fputs("pc-" KEY_C "\n", f);
    fclose(f);
    CHECK(pt_session_remove_command(KEY_B, b, sizeof b) > 0);
    CHECK_STR(run(x, b, shell), "");
    CHECK(pt_session_list_command(b, sizeof b) > 0);
    o = run(x, b, shell);
    CHECK(strstr(o, CODEX_ID) == NULL);
    CHECK(strstr(o, "S\t" KEY_C "\t") != NULL);
    /* Remove: tmux session ended, records gone, transcript stays (AC-SESSION-7). */
    CHECK(pt_session_remove_command(KEY_A, b, sizeof b) > 0);
    CHECK_STR(run(x, b, shell), "");
    CHECK(pt_session_list_command(b, sizeof b) > 0);
    o = run(x, b, shell);
    CHECK(strstr(o, KEY_A) == NULL);
    snprintf(p, sizeof p, "%s/.claude/projects/-work-a/" KEY_A ".jsonl", x->home);
    CHECK(access(p, F_OK) == 0);
}

PT_TEST(session_scripts_zsh_login_shell, "AC-SESSION-1 AC-SESSION-2 AC-SESSION-3 AC-SESSION-4 AC-SESSION-5 AC-SESSION-7 BR-SESSION-1 EF-SESSION-2") {
    list_fixture_test("/bin/zsh");
}
PT_TEST(session_scripts_dash_shell, "AC-SESSION-1 AC-SESSION-2 AC-SESSION-3 AC-SESSION-5") {
    list_fixture_test("/bin/dash");
}

/* A stand-in find that logs each call, to count searches. */
static void log_find(box *x) {
    char f[512];
    snprintf(f, sizeof f, "%s/find", x->bin);
    FILE *t = fopen(f, "w");
    fputs("#!/bin/sh\necho find >> \"$HOME/finds\"\nexec /usr/bin/find \"$@\"\n", t);
    fclose(t);
    chmod(f, 0755);
}

static int count_finds(box *x) {
    char f[512];
    snprintf(f, sizeof f, "%s/finds", x->home);
    int n = 0, c;
    FILE *t = fopen(f, "r");
    if (!t) return 0;
    while ((c = fgetc(t)) != EOF) if (c == '\n') n++;
    fclose(t);
    unlink(f);
    return n;
}

PT_TEST(session_list_searches_only_for_live_sessions, "BR-SESSION-2") {
    box *x = make_box();
    log_find(x);
    char b[16384], p[512];
    CHECK(pt_session_launch_command(PT_AGENT_CODEX, KEY_A, x->home, b, sizeof b) > 0);
    CHECK_STR(run(x, b, "/bin/sh"), "");
    count_finds(x);
    CHECK(pt_session_list_command(b, sizeof b) > 0);
    run(x, b, "/bin/sh");
    CHECK_INT(count_finds(x), 1); /* one search after the stop: the agent can have written before it stopped */
    run(x, b, "/bin/sh");
    run(x, b, "/bin/sh");
    CHECK_INT(count_finds(x), 0); /* then none */
    snprintf(p, sizeof p, "%s/live", x->home);
    FILE *f = fopen(p, "w");
    fputs("pc-" KEY_A "\n", f);
    fclose(f);
    run(x, b, "/bin/sh");
    CHECK_INT(count_finds(x), 1); /* live and not linked: one search per read */
}

PT_TEST(session_list_limit_follows_the_last_attach, "AC-SESSION-2") {
    box *x = make_box();
    char b[16384], key[64];
    for (int i = 0; i < 51; i++) {
        snprintf(key, sizeof key, "aaaaaaaa-aaaa-4aaa-8aaa-%012d", i);
        CHECK(pt_session_launch_command(PT_AGENT_CLAUDE, key, x->home, b, sizeof b) > 0);
        run(x, b, "/bin/sh");
    }
    sleep(1);
    snprintf(key, sizeof key, "aaaaaaaa-aaaa-4aaa-8aaa-%012d", 1);
    CHECK(pt_session_launch_command(PT_AGENT_CLAUDE, key, x->home, b, sizeof b) > 0);
    run(x, b, "/bin/sh");
    CHECK(pt_session_list_command(b, sizeof b) > 0);
    char *o = run(x, b, "/bin/sh");
    CHECK(strstr(o, key) != NULL); /* an old session opened again comes back into the list */
    int rows = 0;
    for (char *q = o; (q = strstr(q, "S\t")) != NULL; q += 2) rows++;
    CHECK_INT(rows, 50);
}

PT_TEST(session_wrong_directory_starts_no_agent, "EF-LAUNCH-1") {
    box *x = make_box();
    char b[16384], dir[400], p[512];
    snprintf(dir, sizeof dir, "%s/no-such-folder", x->home);
    CHECK(pt_session_launch_command(PT_AGENT_CLAUDE, KEY_A, dir, b, sizeof b) > 0);
    char *o = run(x, b, "/bin/sh");
    CHECK(strstr(o, "padterm: directory not found: ") != NULL);
    CHECK(strstr(slurp(x->log), "new") == NULL);
    snprintf(p, sizeof p, "%s/.padterm/sessions/" KEY_A, x->home);
    CHECK(access(p, F_OK) != 0); /* no record of a session that never started */
    /* A folder removed later: the record stays, the agent does not start elsewhere. */
    sh("mkdir -p %s/gone%.0s%.0s", x->home, "", "");
    snprintf(dir, sizeof dir, "%s/gone", x->home);
    CHECK(pt_session_launch_command(PT_AGENT_CLAUDE, KEY_B, dir, b, sizeof b) > 0);
    CHECK_STR(run(x, b, "/bin/sh"), "");
    unlink(x->log);
    snprintf(p, sizeof p, "%s", dir);
    sh("rm -rf %s%.0s%.0s", p, "", "");
    o = run(x, b, "/bin/sh");
    CHECK(strstr(o, "padterm: directory not found: ") != NULL);
    CHECK(strstr(slurp(x->log), "new") == NULL);
}

PT_TEST(session_records_with_odd_values, "BR-SESSION-3 EF-SESSION-2") {
    box *x = make_box();
    char b[16384], dir[400], p[512];
    /* A record with an unknown agent starts nothing. */
    sh("mkdir -p %s/.padterm/sessions %s/.padterm/seen%.0s", x->home, x->home, "");
    snprintf(p, sizeof p, "%s/.padterm/sessions/" KEY_A, x->home);
    FILE *f = fopen(p, "w");
    fputs("vim\n/\n", f);
    fclose(f);
    CHECK(pt_session_launch_command(PT_AGENT_CLAUDE, KEY_A, "~", b, sizeof b) > 0);
    CHECK(strstr(run(x, b, "/bin/sh"), "padterm: bad record") != NULL);
    CHECK(strstr(slurp(x->log), "new") == NULL);
    /* A rollout file name is not code: the agent starts new, and nothing runs. */
    sh("mkdir -p %s/w%.0s%.0s", x->home, "", "");
    snprintf(dir, sizeof dir, "%s/w", x->home);
    CHECK(pt_session_launch_command(PT_AGENT_CODEX, KEY_B, dir, b, sizeof b) > 0);
    run(x, b, "/bin/sh");
    struct stat st; /* BR-SESSION: other users of the server must not read titles and directories */
    snprintf(p, sizeof p, "%s/.padterm", x->home);
    CHECK_INT(stat(p, &st), 0);
    CHECK_INT(st.st_mode & 0777, 0700);
    unlink(x->log);
    snprintf(p, sizeof p, "%s/.padterm/sessions/" KEY_B, x->home);
    char line[800], real[512];
    snprintf(line, sizeof line, "cd '%s' && pwd -P", dir);
    FILE *pw = popen(line, "r");
    real[fread(real, 1, sizeof real - 1, pw)] = 0;
    pclose(pw);
    real[strcspn(real, "\n")] = 0;
    f = fopen(p, "w");
    fprintf(f, "codex\n%s\n%s/.codex/sessions/rollout-2026-11-04T00-12-06-$(touch pwned).jsonl\n", real, x->home);
    fclose(f);
    char bad[600];
    snprintf(bad, sizeof bad, "%s/.codex/sessions/rollout-2026-11-04T00-12-06-$(touch pwned).jsonl", x->home);
    f = fopen(bad, "w");
    fputs("{}\n", f);
    fclose(f);
    run(x, b, "/bin/sh");
    CHECK(strstr(slurp(x->log), "cmd=codex --approve-for-me || exec") != NULL);
    /* A directory with a quote and a trailing space links to its rollout, where JSON escapes the quote. */
    sh("mkdir -p '%s/q\"x '%.0s%.0s", x->home, "", "");
    snprintf(dir, sizeof dir, "%s/q\"x ", x->home);
    CHECK(pt_session_launch_command(PT_AGENT_CODEX, KEY_C, dir, b, sizeof b) > 0);
    CHECK_STR(run(x, b, "/bin/sh"), "");
    sleep(1);
    snprintf(line, sizeof line, "cd '%s' && pwd -P", dir);
    pw = popen(line, "r");
    real[fread(real, 1, sizeof real - 1, pw)] = 0;
    pclose(pw);
    real[strcspn(real, "\n")] = 0;
    char *q = strchr(real, '"');
    CHECK(q != NULL);
    *q = 0;
    snprintf(p, sizeof p, "%s/.codex/sessions/rollout-2026-11-04T10-00-00-" CODEX_ID ".jsonl", x->home);
    f = fopen(p, "w");
    fprintf(f, "{\"payload\":{\"cwd\":\"%s\\\"%s\"}}\n", real, q + 1);
    fclose(f);
    snprintf(p, sizeof p, "%s/live", x->home);
    f = fopen(p, "w");
    fputs("pc-" KEY_C "\n", f);
    fclose(f);
    CHECK(pt_session_list_command(b, sizeof b) > 0);
    run(x, b, "/bin/sh");
    snprintf(p, sizeof p, "%s/.padterm/sessions/" KEY_C, x->home);
    CHECK(strstr(slurp(p), "rollout-2026-11-04T10-00-00-" CODEX_ID) != NULL);
}

PT_TEST(session_stopped_before_any_list_read_gets_its_name, "AC-SESSION-3") {
    box *x = make_box();
    char b[16384], p[512];
    CHECK(pt_session_launch_command(PT_AGENT_CLAUDE, KEY_A, x->home, b, sizeof b) > 0);
    CHECK_STR(run(x, b, "/bin/sh"), "");
    /* The agent wrote its transcript and exited while the terminal covered the list: tmux has no session now. */
    sleep(1);
    snprintf(p, sizeof p, "%s/.claude/projects/-work-a/" KEY_A ".jsonl", x->home);
    FILE *f = fopen(p, "w");
    fputs("{\"type\":\"ai-title\",\"aiTitle\":\"Done work\",\"sessionId\":\"" KEY_A "\"}\n", f);
    fclose(f);
    CHECK(pt_session_list_command(b, sizeof b) > 0);
    char *o = run(x, b, "/bin/sh");
    CHECK(strstr(o, "\"aiTitle\":\"Done work\"") != NULL);
    CHECK(strstr(o, "R\t") == NULL);
}

PT_TEST(session_stopped_codex_record_takes_no_later_rollout, "EF-SESSION-2") {
    box *x = make_box();
    char list[16384], launch[16384], p[512], line[800], real[512];
    CHECK(pt_session_launch_command(PT_AGENT_CODEX, KEY_A, x->home, launch, sizeof launch) > 0);
    CHECK(pt_session_list_command(list, sizeof list) > 0);
    CHECK_STR(run(x, launch, "/bin/sh"), "");
    run(x, list, "/bin/sh"); /* stopped, nothing to find: searched once */
    unlink(x->log);
    sleep(1);
    /* Later, codex runs from another terminal in that directory. */
    snprintf(line, sizeof line, "cd '%s' && pwd -P", x->home);
    FILE *pw = popen(line, "r");
    real[fread(real, 1, sizeof real - 1, pw)] = 0;
    pclose(pw);
    real[strcspn(real, "\n")] = 0;
    snprintf(p, sizeof p, "%s/.codex/sessions/rollout-2026-11-04T10-00-00-" CODEX_ID ".jsonl", x->home);
    FILE *f = fopen(p, "w");
    fprintf(f, "{\"payload\":{\"cwd\":\"%s\"}}\n", real);
    fclose(f);
    CHECK(strstr(run(x, list, "/bin/sh"), CODEX_ID) == NULL);
    /* A tap starts a new Codex, not the other conversation. */
    CHECK_STR(run(x, launch, "/bin/sh"), "");
    CHECK(strstr(slurp(x->log), "cmd=codex --approve-for-me || exec") != NULL);
    /* And while it runs, that older rollout is still not its own. */
    snprintf(p, sizeof p, "%s/live", x->home);
    f = fopen(p, "w");
    fputs("pc-" KEY_A "\n", f);
    fclose(f);
    CHECK(strstr(run(x, list, "/bin/sh"), CODEX_ID) == NULL);
}
