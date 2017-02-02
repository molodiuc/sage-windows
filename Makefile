TARGETS=env-build env-runtime cygwin-build cygwin-runtime sage-build \
        sage-runtime cygwin-extras-runtime
.PHONY: all $(TARGETS)

############################ Configurable Variables ###########################

# Can be x86 or x86_64
ARCH?=x86_64

SAGE_VERSION?=7.4
SAGE_BRANCH?=$(SAGE_VERSION)

# Output paths
DIST?=dist
DOWNLOAD?=download
ENVS?=envs
STAMPS?=.stamps

# Path to the Inno Setup executable
ISCC?="/cygdrive/c/Program Files (x86)/Inno Setup 5/ISCC.exe"

################################################################################

# Actual targets for the main build stages (the stamp files)
env-build=$(STAMPS)/env-build-$(ARCH)
env-runtime=$(STAMPS)/env-runtime-$(SAGE_VERSION)-$(ARCH)
cygwin-build=$(STAMPS)/cygwin-build-$(ARCH)
cygwin-runtime=$(STAMPS)/cygwin-runtime-$(SAGE_VERSION)-$(ARCH)
sage-build=$(STAMPS)/sage-build-$(SAGE_VERSION)-$(ARCH)
sage-runtime=$(STAMPS)/sage-runtime-$(SAGE_VERSION)-$(ARCH)
cygwin-runtime-extras=$(STAMPS)/cygwin-runtime-extras-$(SAGE_VERSION)-$(ARCH)

###############################################################################

# Resource paths
CYGWIN_EXTRAS=cygwin_extras
RESOURCES=resources
DOT_SAGE=dot_sage
ICONS:=$(wildcard $(RESOURCES)/*.bmp) $(wildcard $(RESOURCES)/*.ico)

ENV_BUILD_DIR=$(ENVS)/build-$(ARCH)
ENV_RUNIME_DIR=$(ENVS)/runtime-$(SAGE_VERSION)-$(ARCH)

SAGE_GIT=git://git.sagemath.org/sage.git
SAGE_ROOT=/opt/sagemath-$(SAGE_VERSION)
SAGE_ROOT_BUILD=$(ENV_BUILD_DIR)$(SAGE_ROOT)
SAGE_ROOT_RUNTIME=$(ENV_RUNTIME_DIR)$(SAGE_ROOT)

# Outputs representing success in the Sage build process
SAGE_CONFIGURE=$(SAGE_ROOT_BUILD)/configure
SAGE_MAKEFILE=$(SAGE_ROOT_BUILD)/build/make/Makefile
SAGE_STARTED=$(SAGE_ROOT_BUILD)/local/etc/sage-started.txt

# Files used as input to ISCC
SAGEMATH_ISS=SageMath.iss
SOURCES:=$(SAGEMATH_ISS) $(DOT_SAGE) $(ICONS)

# URL to download the Cygwin setup.exe
CYGWIN_SETUP_NAME=setup-$(ARCH).exe
CYGWIN_SETUP=$(DOWNLOAD)/$(CYGWIN_SETUP_NAME)
CYGWIN_SETUP_URL=https://cygwin.com/$(CYGWIN_SETUP_NAME)
CYGWIN_MIRROR=ftp://mirrors.kernel.org/sourceware/cygwin/

SAGE_INSTALLER=$(DIST)/SageMath-$(SAGE_VERSION).exe

TOOLS=tools
SUBCYG=$(TOOLS)/subcyg

DIRS=$(DIST) $(DOWNLOAD) $(ENVS) $(STAMPS)


################################################################################

all: $(SAGE_INSTALLER)

$(SAGE_INSTALLER): $(ISCC) $(SOURCES) $(env-runtime) | $(DIST)
	cd $(CUDIR)
	"$(ISCC)" /DSageVersion=$(SAGE_VERSION) /DEnvsDir="$(ENVS)" \
		/DOutputDir="$(DIST)" $(SAGEMATH_ISS)


$(foreach target,$(TARGETS),$(eval $(target): $$($(target))))


$(env-runtime): $(cygwin-runtime) $(sage-runtime) $(cygwin-runtime-extras)
	(cd $(ENV_RUNTIME_DIR) && find . -type l) > $(ENV_RUNTIME_DIR)/etc/symlinks.lst
	@touch $@


$(sage-runtime): $(SAGE_ROOT_RUNTIME)

$(SAGE_ROOT_RUNTIME): $(cygwin-runtime) $(sage-build)
	[ -d $(dir $@) ] || mkdir $(dir $@)
	cp -r $(SAGE_ROOT_BUILD) $(dir $@)
	(cd $@ && rm -rf bootstrap config* logs m4 Makefile \
		upstream local/var/tmp/sage/build/* local/var/lock/* \
		src/build local/share/doc/sage/doctrees .git*)
	@touch $@


$(env-build): $(cygwin-build) $(sage-build)
	@touch $@


# TODO: This doesn't build the documentation yet
$(sage-build): $(cygwin-build) $(SAGE_STARTED)
	@touch $@


$(cygwin-runtime-extras): $(cygwin-runtime)
	cp -r $(CYGWIN_EXTRAS)/* $(ENV_RUNTIME_DIR)
	echo "SAGE_VERSION=$(SAGE_VERSION)" > $(ENV_RUNTIME_DIR)/etc/sage-version
	echo 'none /tmp usertemp binary,posix=0 0 0' >> $(ENV_RUNTIME_DIR)/etc/fstab
	echo 'C:\Users /home ntfs binary,posix=1,acl 0 0' >> $(ENV_RUNTIME_DIR)/etc/fstab
	@touch $@


$(STAMPS)/cygwin-%: $(ENVS)/% | $(STAMPS)
	@touch $@
	

$(ENVS)/%: cygwin-sage-%.list $(CYGWIN_SETUP)
	"$(CYGWIN_SETUP)" --site $(CYGWIN_MIRROR) \
		--local-package-dir "$$(cygpath -w -a $(DOWNLOAD))" \
		--root "$$(cygpath -w -a $@)" \
		--arch $(ARCH) --no-admin --no-shortcuts --quiet-mode \
		--packages $$($(TOOLS)/setup-package-list $<)
	# Install symlinks for CCACHE
	if [ -x $@/usr/bin/ccache ]; then \
		ln -s /usr/bin/ccache $@/usr/local/bin/gcc; \
		ln -s /usr/bin/ccache $@/usr/local/bin/g++; \
	fi
	# A bit of cleanup
	rm -f $@/Cygwin*.{bat,ico}


$(SAGE_STARTED): $(SAGE_MAKEFILE)
	$(SUBCYG) "$(ENV_BUILD_DIR)" "(cd $(SAGE_ROOT) && \
	    (SAGE_NUM_THREADS=1 SAGE_INSTALL_CCACHE=yes CCACHE="$$HOME/.ccache" \
		SAGE_FAT_BINARY=yes SAGE_ATLAS_LIB=/lib \
		make start))"


$(SAGE_MAKEFILE): $(SAGE_CONFIGURE)
	$(SUBCYG) "$(ENV_BUILD_DIR)" "(cd $(SAGE_ROOT) && ./configure --with-blas=atlas)"


$(SAGE_CONFIGURE): | $(SAGE_ROOT_BUILD)
	$(SUBCYG) "$(ENV_BUILD_DIR)" "(cd $(SAGE_ROOT) && make configure)"


$(SAGE_ROOT_BUILD): $(cygwin-build)
	[ -d $(dir $(SAGE_ROOT_BUILD)) ] || mkdir $(dir $(SAGE_ROOT_BUILD))
	$(SUBCYG) "$(ENV_BUILD_DIR)" "(cd /opt && git clone --single-branch --branch $(SAGE_BRANCH) $(SAGE_GIT) $(SAGE_ROOT))"


$(CYGWIN_SETUP): | $(DOWNLOAD)
	(cd $(DOWNLOAD) && wget "$(CYGWIN_SETUP_URL)")
	chmod +x $(CYGWIN_SETUP)


$(DIRS):
	mkdir "$@"