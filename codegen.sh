#!/bin/bash

set -e

rm -r src/protocol 
gleam run -m chrobot/internal/generate_bindings
gleam format
gleam check
echo "Done & Dusted! 🧹"