
ASM_FILES        := $(wildcard src/*/*.asm)
COMMON_INC_FILES := $(wildcard src/*.inc src/_common/*.inc)

MODE7_TILES_SRC	 := $(wildcard resources/*/*mode7-tiles.png)
8BPP_TILES_SRC	 := $(wildcard resources/*/*8bpp-tiles.png)
4BPP_TILES_SRC	 := $(wildcard resources/*/*4bpp-tiles.png)
2BPP_TILES_SRC	 := $(wildcard resources/*/*2bpp-tiles.png)
BIN_RESOURCES_SRC:= $(wildcard resources/*/*.asm)

MODE7_TILES      := $(patsubst resources/%.png,gen/%.tiles, $(MODE7_TILES_SRC))
8BPP_TILES       := $(patsubst resources/%.png,gen/%.tiles, $(8BPP_TILES_SRC))
4BPP_TILES       := $(patsubst resources/%.png,gen/%.tiles, $(4BPP_TILES_SRC))
2BPP_TILES       := $(patsubst resources/%.png,gen/%.tiles, $(2BPP_TILES_SRC))
BIN_RESOURCES    := $(patsubst resources/%.asm,gen/%.bin, $(BIN_RESOURCES_SRC))

MODE7_PALETTES   := $(patsubst resources/%.png,gen/%.pal, $(MODE7_TILES_SRC))
8BPP_PALETTES    := $(patsubst resources/%.png,gen/%.pal, $(8BPP_TILES_SRC))
4BPP_PALETTES    := $(patsubst resources/%.png,gen/%.pal, $(4BPP_TILES_SRC))
2BPP_PALETTES    := $(patsubst resources/%.png,gen/%.pal, $(2BPP_TILES_SRC))


RESOURCES := $(MODE7_TILES) $(MODE7_PALETTES) \
             $(8BPP_TILES) $(8BPP_PALETTES) \
             $(4BPP_TILES) $(4BPP_PALETTES) \
             $(2BPP_TILES) $(2BPP_PALETTES) \
             $(BIN_RESOURCES)


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
  BASS_DIR     := bass-untech
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
	$(bass) -strict -o $@ -sym $(@:.sfc=.sym) $<
else
bin/%.sfc: $(call find-sources, %)
	$(bass) -strict -o $@ $<
endif



ifdef BASS_DIR
  tools: bass

  $(BINARIES): bass
  $(BIN_RESOURCES): bass

  .INTERMEDIATE: bass
  bass: $(call rwildcard_all $(BASS_DIR))
	$(MAKE) -C '$(BASS_DIR)/bass'

  $(bass): bass
endif



.PHONY: resources
resources: $(RESOURCES)
$(BINARIES): $(RESOURCES)

gen/%-2bpp-tiles.tiles gen/%-2bpp-tiles.pal: resources/%-2bpp-tiles.png
	python3 tools/png2snes.py -f 2bpp -t gen/$*-2bpp-tiles.tiles -p gen/$*-2bpp-tiles.pal $<

gen/%-4bpp-tiles.tiles gen/%-4bpp-tiles.pal: resources/%-4bpp-tiles.png
	python3 tools/png2snes.py -f 4bpp -t gen/$*-4bpp-tiles.tiles -p gen/$*-4bpp-tiles.pal $<

gen/%-8bpp-tiles.tiles gen/%-8bpp-tiles.pal: resources/%-8bpp-tiles.png
	python3 tools/png2snes.py -f 8bpp -t gen/$*-8bpp-tiles.tiles -p gen/$*-8bpp-tiles.pal $<

gen/%-mode7-tiles.tiles gen/%-mode7-tiles.pal: resources/%-mode7-tiles.png
	python3 tools/png2snes.py -f mode7 -t gen/$*-mode7-tiles.tiles -p gen/$*-mode7-tiles.pal $<

$(BIN_RESOURCES): gen/%.bin: resources/%.asm
	$(bass) -strict -o $@ $<



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
	$(MAKE) -C '$(BASS_DIR)/bass' clean
endif

