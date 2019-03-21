#!/usr/bin/env bash

make clean
make
gzdoom -iwad doom2 -file build/6dof-player.pk3 -warp 1
