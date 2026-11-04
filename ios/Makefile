# PadTerm iOS app (theos). Build: make -C ios package   (needs THEOS=~/theos and GNU make)
TARGET := iphone:clang:9.3:6.0
ARCHS := armv7
# See scripts/make_ios_sdk.sh: the 9.3 SDK with stubs the current Apple linker accepts for armv7.
SYSROOT := $(THEOS)/sdks/iPhoneOS9.3-armv7.sdk
include $(THEOS)/makefiles/common.mk

ROOT := $(CURDIR)/..
IOS_PREFIX := $(ROOT)/third_party/prefix/ios-armv7

APPLICATION_NAME = PadTerm
PadTerm_FILES = $(wildcard src/*.m)
# NFR-2: an API newer than iOS 6.0 is a build error. Module-map warning: old SDK headers with a new clang.
# -mno-thumb: see IOS_FLAGS in ../Makefile; this linker cannot make Thumb code pointers.
PadTerm_CFLAGS = -mno-thumb -fobjc-arc -Werror=unguarded-availability -Wno-deprecated-module-dot-map \
	-I$(ROOT)/core -I$(ROOT)/render -I$(ROOT)/third_party/src/libvterm-0.3.3-pt/include
# SELFTEST=1: test-only build that the Mac drives over USB (tests/device). Never ship it.
ifeq ($(SELFTEST),1)
PadTerm_FILES += selftest/PTSelfTest.m selftest/pt_metrics.m
PadTerm_CFLAGS += -DPT_SELFTEST -Iselftest -Isrc
endif
PadTerm_LDFLAGS = $(ROOT)/build/ios/libpadcore.a $(IOS_PREFIX)/lib/libssh2.a $(IOS_PREFIX)/lib/libssl.a \
	$(IOS_PREFIX)/lib/libcrypto.a
PadTerm_FRAMEWORKS = UIKit Foundation CoreGraphics CoreText QuartzCore

include $(THEOS_MAKE_PATH)/application.mk

before-all::
	$(MAKE) -C $(ROOT) ios-lib
	mkdir -p Resources
	$(ROOT)/scripts/make_art.sh
	rm -f Resources/Icon-*.png
	cp $(ROOT)/assets/art/build/Icon-*.png '$(ROOT)/assets/art/build/Default-Portrait~ipad.png' '$(ROOT)/assets/art/build/Default-Landscape~ipad.png' Resources/
	mkdir -p Resources/Licenses
	cp $(ROOT)/LICENSE Resources/Licenses/PadTerm-LICENSE.txt
	cp $(ROOT)/third_party/licenses/*.txt Resources/Licenses/
	cp $(ROOT)/assets/fonts/DejaVuSansMono.ttf $(ROOT)/assets/fonts/DejaVuSansMono-Bold.ttf \
	   $(ROOT)/assets/fonts/DejaVu-LICENSE.txt Resources/
