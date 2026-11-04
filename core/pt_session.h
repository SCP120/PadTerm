#ifndef PT_SESSION_H
#define PT_SESSION_H
#include "pt_launch.h"
#include <stddef.h>

/* 1 if key is a lower-case or upper-case UUID text (8-4-4-4-12), else 0 (BR-SESSION-3). */
int pt_session_key_valid(const char *key);

/* Start or continue the session `key` of a Claude or Codex agent (design "Sessions"). dir is used only when
 * the server has no record of the key yet. Returns the length or PT_ERR_INVALID / PT_ERR_NOSPACE. */
int pt_session_launch_command(pt_agent agent, const char *key, const char *dir, char *out, size_t outlen);

/* Print the S / T / R lines of all recorded sessions. */
int pt_session_list_command(char *out, size_t outlen);

/* End the tmux session and remove the records of `key`. The agent's transcript stays. */
int pt_session_remove_command(const char *key, char *out, size_t outlen);

/* The session name inside a terminal title. Claude: "<symbol> name" ("Claude Code" is not a name).
 * Codex: "name | <directory name>", with an optional leading symbol. Returns 1 and fills out, or 0 if the
 * title has no name in it. */
int pt_session_clean_title(pt_agent agent, const char *title, char *out, size_t outlen);

#endif
