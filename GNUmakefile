
ASM_FILES        := $(wildcard src/*/*.asm src/*/*/*.asm)
COMMON_INC_FILES := $(wildcard src/*.inc src/_common/*.inc)

MODE7_TILES_SRC	 := $(wildcard resources/*/*mode7-tiles.png)
8BPP_TILES_SRC	 := $(wildcard resources/*/*8bpp-tiles.png)
4BPP_TILES_SRC	 := $(wildcard resources/*/*4bpp-tiles.png)
2BPP_TILES_SRC	 := $(wildcard resources/*/*2bpp-tiles.png)
1BPP_TILES_SRC	 := $(wildcard resources/*/*1bpp-tiles.png)
BIN_RESOURCES_SRC:= $(wildcard resources/*/*.asm)

MODE7_TILES      := $(patsubst resources/%.png,gen/%.tiles, $(MODE7_TILES_SRC))
8BPP_TILES       := $(patsubst resources/%.png,gen/%.tiles, $(8BPP_TILES_SRC))
4BPP_TILES       := $(patsubst resources/%.png,gen/%.tiles, $(4BPP_TILES_SRC))
2BPP_TILES       := $(patsubst resources/%.png,gen/%.tiles, $(2BPP_TILES_SRC))
1BPP_TILES       := $(patsubst resources/%.png,gen/%.tiles, $(1BPP_TILES_SRC))

BIN_RESOURCES    := $(patsubst resources/%.asm,gen/%.bin, $(BIN_RESOURCES_SRC))

MODE7_PALETTES   := $(patsubst resources/%.png,gen/%.pal, $(MODE7_TILES_SRC))
8BPP_PALETTES    := $(patsubst resources/%.png,gen/%.pal, $(8BPP_TILES_SRC))
4BPP_PALETTES    := $(patsubst resources/%.png,gen/%.pal, $(4BPP_TILES_SRC))
2BPP_PALETTES    := $(patsubst resources/%.png,gen/%.pal, $(2BPP_TILES_SRC))
1BPP_PALETTES    := $(patsubst resources/%.png,gen/%.pal, $(1BPP_TILES_SRC))

4BPP_IMAGES	 := inidisp-fadein-fadeout/game inidisp-fadein-fadeout/map
2BPP_IMAGES	 := 

4BPP_IMAGES	 += hdma-textbox-wipe/bg1 hdma-textbox-wipe/bg2
2BPP_IMAGES	 += hdma-textbox-wipe/bg3

2BPP_IMAGES	 += hdma-hoffset-examples/vertical-bar-2bpp
2BPP_IMAGES	 += hdma-hoffset-examples/two-vertical-bars-2bpp
2BPP_IMAGES	 += hdma-hoffset-examples/shear-titlescreen-2bpp


BINARIES  := $(patsubst src/%.asm,bin/%.sfc,$(ASM_FILES))

RESOURCES := $(MODE7_TILES) $(MODE7_PALETTES) \
             $(8BPP_TILES) $(8BPP_PALETTES) \
             $(4BPP_TILES) $(4BPP_PALETTES) \
             $(2BPP_TILES) $(2BPP_PALETTES) \
             $(1BPP_TILES) $(1BPP_PALETTES) \
             $(patsubst %,gen/%.4bpp,$(4BPP_IMAGES)) $(patsubst %,gen/%.tilemap,$(4BPP_IMAGES)) $(patsubst %,gen/%.palette,$(4BPP_IMAGES)) \
             $(patsubst %,gen/%.2bpp,$(2BPP_IMAGES)) $(patsubst %,gen/%.tilemap,$(2BPP_IMAGES)) $(patsubst %,gen/%.palette,$(2BPP_IMAGES)) \
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


.PHONY: roms
roms: $(BINARIES)


ifeq ($(VANILLA_BASS), n)
bin/%.sfc: src/%.asm $(COMMON_INC_FILES) tools/write-sfc-checksum.py
	$(bass) -strict -o $@ -sym $(@:.sfc=.sym) $<
	python3 tools/write-sfc-checksum.py --lorom $@

else
bin/%.sfc: src/%.asm $(COMMON_INC_FILES) tools/write-sfc-checksum.py
	$(bass) -strict -o $@ $<
	python3 tools/write-sfc-checksum.py --lorom $@
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


VMAIN_REMAPPING_INC_FILES := $(wildcard src/vmain-address-remapping/*.inc)
VMAIN_REMAPPING_BINARIES := $(filter bin/vmain-address-remapping/%.sfc, $(BINARIES))

$(VMAIN_REMAPPING_BINARIES): $(VMAIN_REMAPPING_INC_FILES)


QUICK_MODEL_1_DMA_CRASH_INC_FILES := $(wildcard src/hardware-glitch-tests/quick-model-1-dma-crash/*.inc)
QUICK_MODEL_1_DMA_CRASH_BINARIES := $(filter bin/hardware-glitch-tests/quick-model-1-dma-crash/%.sfc, $(BINARIES))

$(QUICK_MODEL_1_DMA_CRASH_BINARIES): $(QUICK_MODEL_1_DMA_CRASH_INC_FILES)



.PHONY: resources
resources: $(RESOURCES)
$(BINARIES): $(RESOURCES)

gen/%-1bpp-tiles.tiles gen/%-1bpp-tiles.pal: resources/%-1bpp-tiles.png
	python3 tools/png2snes.py -f 1bpp -t gen/$*-1bpp-tiles.tiles -p gen/$*-1bpp-tiles.pal $<

gen/%-2bpp-tiles.tiles gen/%-2bpp-tiles.pal: resources/%-2bpp-tiles.png
	python3 tools/png2snes.py -f 2bpp -t gen/$*-2bpp-tiles.tiles -p gen/$*-2bpp-tiles.pal $<

gen/%-4bpp-tiles.tiles gen/%-4bpp-tiles.pal: resources/%-4bpp-tiles.png
	python3 tools/png2snes.py -f 4bpp -t gen/$*-4bpp-tiles.tiles -p gen/$*-4bpp-tiles.pal $<

gen/%-8bpp-tiles.tiles gen/%-8bpp-tiles.pal: resources/%-8bpp-tiles.png
	python3 tools/png2snes.py -f 8bpp -t gen/$*-8bpp-tiles.tiles -p gen/$*-8bpp-tiles.pal $<

gen/%-mode7-tiles.tiles gen/%-mode7-tiles.pal: resources/%-mode7-tiles.png
	python3 tools/png2snes.py -f mode7 -t gen/$*-mode7-tiles.tiles -p gen/$*-mode7-tiles.pal $<


gen/%.4bpp gen/%.tilemap gen/%.palette: resources/%.png resources/%-palette.png tools/image2snes.py tools/_snes.py
	python3 tools/image2snes.py -f 4bpp -t gen/$*.4bpp -m gen/$*.tilemap -p gen/$*.palette resources/$*.png resources/$*-palette.png

gen/%.2bpp gen/%.tilemap gen/%.palette: resources/%.png resources/%-palette.png tools/image2snes.py tools/_snes.py
	python3 tools/image2snes.py -f 2bpp -t gen/$*.2bpp -m gen/$*.tilemap -p gen/$*.palette resources/$*.png resources/$*-palette.png


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

