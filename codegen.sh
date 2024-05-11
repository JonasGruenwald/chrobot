#!/bin/bash
rm -r src/protocol 
set -e
gleam run -m chrobot/internal/generate_bindings
gleam format
# gleam check
echo "Done & Dusted! 🧹"