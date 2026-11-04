/* Review finding N1: a signal during a setup wait must not look like a cancel (= user close). */
#include "pt_test.h"
#include "../../core/pt_error.h"
#include "../../core/pt_ssh.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <pthread.h>
#include <signal.h>
#include <sys/socket.h>
#include <unistd.h>

static void on_usr1(int sig) { (void)sig; }
static void *send_signal(void *arg) { usleep(200 * 1000); pthread_kill(*(pthread_t *)arg, SIGUSR1); return NULL; }

PT_TEST(signal_during_handshake_is_not_cancel, "BR-RECONNECT-1") {
    struct sigaction sa = {0};
    sa.sa_handler = on_usr1; /* no SA_RESTART: select returns EINTR */
    sigaction(SIGUSR1, &sa, NULL);
    int l = socket(AF_INET, SOCK_STREAM, 0); /* accepts TCP, never sends a banner */
    struct sockaddr_in a = {.sin_family = AF_INET, .sin_port = 0};
    inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
    CHECK(bind(l, (struct sockaddr *)&a, sizeof a) == 0 && listen(l, 4) == 0);
    socklen_t al = sizeof a; getsockname(l, (struct sockaddr *)&a, &al);
    int cancel[2]; CHECK(pipe(cancel) == 0);  /* nothing is ever written to it */
    pthread_t self = pthread_self(), th;
    pthread_create(&th, NULL, send_signal, &self);
    pt_ssh *s = NULL;
    int rc = pt_ssh_connect("127.0.0.1", ntohs(a.sin_port), 1000, cancel[0], &s);
    pthread_join(th, NULL);
    close(l); close(cancel[0]); close(cancel[1]);
    signal(SIGUSR1, SIG_DFL);
    CHECK_INT(rc, PT_ERR_TIMEOUT); /* was PT_ERR_CANCELLED after the signal */
}
