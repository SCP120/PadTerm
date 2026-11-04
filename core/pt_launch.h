#ifndef PT_LAUNCH_H
#define PT_LAUNCH_H
#include <stddef.h>

typedef enum { PT_AGENT_CLAUDE = 0, PT_AGENT_CODEX = 1, PT_AGENT_SHELL = 2 } pt_agent;

/* tmux session name for the agent: "claude", "codex", "shell". NULL for an unknown value. */
const char *pt_agent_session(pt_agent agent);

/* The remote command (see docs/architecture/designs/padterm.md, "Remote command").
 * Returns the length or PT_ERR_INVALID / PT_ERR_NOSPACE. */
int pt_launch_command(pt_agent agent, const char *dir, char *out, size_t outlen);

#endif
