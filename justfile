# use with https://github.com/casey/just

default:
    @just --list

install-deps:
    #!/usr/bin/env sh
    cd external
    git clone https://github.com/jockus/odin-portaudio/
    git clone https://github.com/PortAudio/portaudio/
    git clone https://github.com/dsego/odin-pa_ringbuffer/
    git clone https://github.com/dsego/odin-pffft
    git clone https://bitbucket.org/jpommier/pffft/

build-pffft:
    #!/usr/bin/env sh
    cd external/pffft
    clang pffft.c pffft.h -c -O2 -Os -fPIC
    ar rcs pffft.a pffft.o
    cp pffft.a ../odin-pffft/

build-pa_ringbuffer:
    #!/usr/bin/env sh
    cd external/portaudio/src/common
    clang pa_ringbuffer.c pa_ringbuffer.h -c -O2 -Os -fPIC
    ar rcs pa_ringbuffer.a pa_ringbuffer.o
    cp pa_ringbuffer.a ../../../odin-pa_ringbuffer/

build-portaudio:
    #!/usr/bin/env sh
    cd external/portaudio
    mkdir build
    cd build
    cmake ..
    cmake --build . --config Release
    cp libportaudio.a ../../../

# just dev [target]
#   (none) raylib renderer
#   sdl    SDL3 GPU renderer with Metal shaders (brew install sdl3)
#   stats  with the signal stats and NSDF plots
#   ios    SDL renderer on the iOS simulator, the first run builds the native deps into external/ios-sim
dev target="":
    #!/usr/bin/env sh
    case "{{target}}" in
        "") odin run app -debug ;;
        sdl) odin run app -debug -define:RENDERER=sdl ;;
        stats) odin run app -debug -define:DEBUG_STATS=true ;;
        ios) sh ios/build-sim.sh ;;
        *) echo "Unknown target '{{target}}', use sdl, stats or ios"; exit 1 ;;
    esac

# just build [sdl]
build target="":
    #!/usr/bin/env sh
    case "{{target}}" in
        "") odin build app -o:speed -microarch:native ;;
        sdl) odin build app -o:speed -microarch:native -define:RENDERER=sdl ;;
        *) echo "Unknown target '{{target}}', use sdl"; exit 1 ;;
    esac
