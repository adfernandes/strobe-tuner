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

dev:
    odin run app -debug

# SDL3 GPU renderer with Metal shaders (brew install sdl3)
dev-sdl:
    odin run app -debug -define:RENDERER=sdl

build:
    odin build app -o:speed -microarch:native

build-sdl:
    odin build app -o:speed -microarch:native -define:RENDERER=sdl

# SDL renderer on the iOS simulator, the first run builds the native deps into external/ios-sim
dev-ios:
    sh ios/build-sim.sh
