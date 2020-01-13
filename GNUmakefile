
rwildcard_all = $(foreach d,$(wildcard $(addsuffix /*,$(1))),$d $(call rwildcard_all, $d))

ASM_FILES        := $(wildcard src/*/*.asm)
DIRS             := $(sort $(dir $(ASM_FILES)))
COMMON_INC_FILES := $(wildcard src/*.inc src/_common/*.inc)


# If VANILLA_BASS is not 'n' then the Makefile will use vanilla bass instead of bass-untech
VANILLA_BASS   ?= n
# If LOCAL_TOOLS is not 'n' then the Makefile will use the tools installed in the user's $PATH
LOCAL_TOOLS    ?= n


ifneq ($(VANILLA_BASS), n)
  bass         ?= bass
else ifneq ($(LOCAL_TOOLS), n)
  bass         := bass-untech
endif

ifndef bass
  BASS_DIR     := tools/bass-untech
  bass         := $(BASS_DIR)/bass/out/bass-untech
endif


.DELETE_ON_ERROR:
.SUFFIXES:

.PHONY: all
all: directories roms


# Create the .sfc target and prerequisites
# Arguments: $1=binary, $2=asm file
define _sfc_target
BINARIES += $1
$1: $2 $(wildcard $(dir $2)/*.inc) $(COMMON_INC_FILES) bin/
endef
$(foreach asm,$(ASM_FILES),$(eval $(call _sfc_target, bin/$(basename $(notdir $(asm))).sfc, $(asm))))

.PHONY: roms
roms: $(BINARIES)


ifeq ($(VANILLA_BASS), n)
bin/%.sfc: $(call find-sources, %)
	$(bass) -strict -o $@ -sym $(@:.sfc=.symbols) $<
else
bin/%.sfc: $(call find-sources, %)
	$(bass) -strict -o $@ $<
endif



ifdef BASS_DIR
  tools: bass

  $(BINARIES): bass

  .INTERMEDIATE: bass
  bass: $(call rwildcard_all $(BASS_DIR))
	$(MAKE) -C "$(BASS_DIR)/bass"

  $(bass): bass
endif


.PHONY: directories
DIRS := $(sort $(dir $(BINARIES) $(RESOURCES) $(TABLE_INCS)))
DIRS := $(patsubst %/,%,$(DIRS))
directories: $(DIRS)
$(DIRS):
  ifeq ($(OS),Windows_NT)
	mkdir $(subst /,\,$@)
  else
	mkdir -p $@
  endif



.PHONY: clean-all
clean-all: clean

.PHONY: clean
clean:
	$(RM) $(BINARIES) $(BINARIES:.sfc=.symbols)
	$(RM) $(sort $(TABLE_INCS))
	$(RM) $(sort $(RESOURCES))

ifdef BASS_DIR
  clean-all: clean-tools

  .PHONY: clean-tools
  clean-tools:
	$(MAKE) -C "$(BASS_DIR)/bass" clean
endif

