/* Start an installed app on the USB-connected iOS device, then detach (the app keeps running).
 * usage: ptlaunch <path to executable on device> <container dir> [KEY=VALUE ...]
 * Needs the developer disk image mounted. Uses only normal lockdown services, no root. */
#include <libimobiledevice/debugserver.h>
#include <libimobiledevice/libimobiledevice.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int cmd(debugserver_client_t c, const char *name, const char *arg) {
    debugserver_command_t k = NULL;
    char *argv[1] = {(char *)arg};
    debugserver_command_new(name, arg ? 1 : 0, arg ? argv : NULL, &k);
    char *resp = NULL;
    debugserver_error_t e = debugserver_client_send_command(c, k, &resp, NULL);
    debugserver_command_free(k);
    printf("%s%s%s -> %s (err %d)\n", name, arg ? " " : "", arg ? arg : "", resp ? resp : "(none)", e);
    int ok = e == DEBUGSERVER_E_SUCCESS && (!resp || strncmp(resp, "E", 1) != 0);
    free(resp);
    return ok;
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: %s exe container [K=V...]\n", argv[0]); return 2; }
    idevice_t dev;
    if (idevice_new(&dev, NULL)) { puts("no device"); return 1; }
    debugserver_client_t c;
    if (debugserver_client_start_service(dev, &c, "ptlaunch")) { puts("no debugserver (mount the image)"); return 1; }
    cmd(c, "QSetMaxPacketSize:", "1024");
    cmd(c, "QSetWorkingDir:", argv[2]);
    char *resp = NULL;
    for (int i = 3; i < argc; i++) {
        const char *env[2] = {argv[i], NULL};
        debugserver_client_set_environment_hex_encoded(c, argv[i], &resp); free(resp); resp = NULL;
        (void)env;
    }
    char *av[2] = {argv[1], NULL};
    debugserver_client_set_argv(c, 1, av, &resp);
    printf("argv -> %s\n", resp ? resp : "(none)"); free(resp);
    if (!cmd(c, "qLaunchSuccess", NULL)) return 1;
    cmd(c, "D", NULL); /* detach: the process runs on */
    debugserver_client_free(c);
    idevice_free(dev);
    return 0;
}
