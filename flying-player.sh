#!/usr/bin/env bash

make clean
make
gzdoom -iwad doom2 -file build/flying-player.pk3 -warp 1
