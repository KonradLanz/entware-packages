#
# Copyright (C) 2026 Konrad Lanz <konrad@greev.com>
# This is free software, licensed under the GNU General Public License v2.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=gh
PKG_VERSION:=2.72.0
PKG_RELEASE:=1

# Architecture-specific source selection
ifeq ($(ARCH),x86_64)
  PKG_ARCH_SUFFIX:=linux_amd64
else ifeq ($(ARCH),aarch64)
  PKG_ARCH_SUFFIX:=linux_arm64
else ifeq ($(ARCH),arm)
  PKG_ARCH_SUFFIX:=linux_armv6
else
  PKG_ARCH_SUFFIX:=linux_amd64
endif

PKG_SOURCE:=gh_$(PKG_VERSION)_$(PKG_ARCH_SUFFIX).tar.gz
PKG_SOURCE_URL:=https://github.com/cli/cli/releases/download/v$(PKG_VERSION)/
PKG_HASH:=skip

PKG_MAINTAINER:=Konrad Lanz <konrad@greev.com>
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

define Package/gh
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=GitHub CLI
  URL:=https://cli.github.com
  DEPENDS:=@(x86_64||aarch64||arm)
endef

define Package/gh/description
  GitHub's official command line tool.
  Brings pull requests, issues, releases and other
  GitHub concepts to the terminal.
endef

# Nothing to compile — prebuilt binary
define Build/Compile
endef

define Package/gh/install
	$(INSTALL_DIR) $(1)/opt/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/bin/gh $(1)/opt/bin/gh
	$(INSTALL_DIR) $(1)/opt/share/gh
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/LICENSE $(1)/opt/share/gh/LICENSE
endef

$(eval $(call BuildPackage,gh))
