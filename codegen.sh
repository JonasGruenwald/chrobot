#!/bin/bash
# rm -r src/protocol 
set -e
gleam run -m codegen/generate_bindings
gleam format
gleam check
echo "Done & Dusted! 🧹"