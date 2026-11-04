# Host (macOS arm64) build of the core, the renderer and the tests.
# The iOS app has its own theos Makefile in ios/.
ROOT     := $(CURDIR)
VTERM    := $(ROOT)/third_party/src/libvterm-0.3.3-pt
PREFIX   := $(ROOT)/third_party/prefix/macos-arm64
OUT      := $(ROOT)/build/host
CC       := xcrun clang
CFLAGS   := -std=c99 -O1 -g -Wall -Wextra -Werror -Wno-unused-parameter -I$(VTERM)/include -I$(PREFIX)/include
VTFLAGS  := -std=c99 -O2 -w -I$(VTERM)/include
FRAMEWORKS := -framework CoreText -framework CoreGraphics -framework CoreFoundation -framework ImageIO
SSHLIBS  := $(PREFIX)/lib/libssh2.a $(PREFIX)/lib/libssl.a $(PREFIX)/lib/libcrypto.a

VTERM_SRC := $(wildcard $(VTERM)/src/*.c)
VTERM_OBJ := $(patsubst $(VTERM)/src/%.c,$(OUT)/vterm/%.o,$(VTERM_SRC))
CORE_OBJ  := $(patsubst core/%.c,$(OUT)/core/%.o,$(wildcard core/*.c))
REND_OBJ  := $(OUT)/render/pt_render.o
UNIT_OBJ  := $(patsubst tests/host/%.c,$(OUT)/tests/%.o,$(wildcard tests/host/*.c))
E2E_OBJ   := $(OUT)/tests/test_e2e.o $(OUT)/tests/pt_test_main.o

.PHONY: all unit e2e clean
all: $(OUT)/unit_tests $(OUT)/e2e_tests

$(VTERM)/src/vterm.c:
	scripts/prepare_libvterm.sh

$(OUT)/vterm/%.o: $(VTERM)/src/%.c
	@mkdir -p $(dir $@)
	$(CC) $(VTFLAGS) -c $< -o $@

$(OUT)/core/%.o: core/%.c core/*.h
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(OUT)/render/%.o: render/%.c render/*.h core/pt_term.h
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(OUT)/tests/%.o: tests/host/%.c tests/host/pt_test.h core/*.h render/*.h
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(OUT)/tests/test_e2e.o: tests/e2e/test_e2e.c tests/host/pt_test.h core/*.h
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(OUT)/unit_tests: $(UNIT_OBJ) $(CORE_OBJ) $(REND_OBJ) $(VTERM_OBJ)
	$(CC) $^ $(SSHLIBS) $(FRAMEWORKS) -o $@

$(OUT)/e2e_tests: $(E2E_OBJ) $(CORE_OBJ) $(VTERM_OBJ)
	$(CC) $^ $(SSHLIBS) -o $@

clean:
	@echo "remove build/host by hand if you want a clean build"

# ---------------------------------------------------------------------------
# iOS armv7 / iOS 6 static library for the app (core + render + libvterm).
IOS_SDK   := $(HOME)/theos/sdks/iPhoneOS9.3-armv7.sdk
IOS_OUT   := $(ROOT)/build/ios
IOS_PREFIX:= $(ROOT)/third_party/prefix/ios-armv7
# NFR-2: any API newer than the iOS 6.0 deployment target is a build error.
# -mno-thumb: ld-27037 writes code pointers (LC_MAIN, ObjC methods, callback tables) without the Thumb bit,
# so Thumb code crashes on the device when it is entered through a pointer. All code is ARM.
IOS_FLAGS := -arch armv7 -mno-thumb -isysroot $(IOS_SDK) -miphoneos-version-min=6.0 -Werror=unguarded-availability
IOS_CFLAGS:= -std=c99 -Os -g -Wall -Wextra -Werror -Wno-unused-parameter $(IOS_FLAGS) -I$(VTERM)/include -I$(IOS_PREFIX)/include
IOS_VTOBJ := $(patsubst $(VTERM)/src/%.c,$(IOS_OUT)/vterm/%.o,$(VTERM_SRC))
IOS_COBJ  := $(patsubst core/%.c,$(IOS_OUT)/core/%.o,$(wildcard core/*.c)) $(IOS_OUT)/render/pt_render.o

.PHONY: ios-lib
ios-lib: $(IOS_OUT)/libpadcore.a

$(IOS_OUT)/vterm/%.o: $(VTERM)/src/%.c
	@mkdir -p $(dir $@)
	$(CC) -std=c99 -Os -w $(IOS_FLAGS) -I$(VTERM)/include -c $< -o $@

$(IOS_OUT)/core/%.o: core/%.c core/*.h
	@mkdir -p $(dir $@)
	$(CC) $(IOS_CFLAGS) -c $< -o $@

$(IOS_OUT)/render/%.o: render/%.c render/*.h core/pt_term.h
	@mkdir -p $(dir $@)
	$(CC) $(IOS_CFLAGS) -c $< -o $@

$(IOS_OUT)/libpadcore.a: $(IOS_COBJ) $(IOS_VTOBJ)
	@rm -f $@
	xcrun libtool -static -o $@ $^

# Profile model + store (Objective-C, Foundation only) on macOS.
$(OUT)/profile_tests: tests/host/test_profile.m tests/host/pt_test_main.c ios/src/PTProfile.m ios/src/PTProfileStore.m ios/src/PTSession.m \
		$(OUT)/core/pt_quote.o $(OUT)/core/pt_ssh.o $(OUT)/core/pt_error.o $(OUT)/core/pt_session.o $(OUT)/core/pt_launch.o
	$(CC) -fobjc-arc -Wall -Werror -Icore -Iios/src -I$(PREFIX)/include $(filter %.m %.c %.o,$^) $(SSHLIBS) -framework Foundation -o $@
all: $(OUT)/profile_tests
