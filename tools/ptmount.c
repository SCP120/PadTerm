#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/lockdown.h>
#include <libimobiledevice/mobile_image_mounter.h>
#include <plist/plist.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    char sig[256]; FILE *f = fopen(argv[1], "rb"); size_t n = fread(sig, 1, sizeof sig, f); fclose(f);
    idevice_t dev; if (idevice_new(&dev, NULL)) { puts("no device"); return 1; }
    mobile_image_mounter_client_t c;
    if (mobile_image_mounter_start_service(dev, &c, "padterm")) { puts("no service"); return 1; }
    plist_t res = NULL;
    mobile_image_mounter_error_t e = mobile_image_mounter_mount_image(c, "/var/mobile/Media/PublicStaging/staging.dimage", sig, (uint16_t)n, "Developer", &res);
    printf("mount_image rc=%d\n", e);
    if (res) { char *x = NULL; uint32_t l = 0; plist_to_xml(res, &x, &l); fwrite(x, 1, l, stdout); }
    mobile_image_mounter_hangup(c); mobile_image_mounter_free(c); idevice_free(dev);
    return e;
}
