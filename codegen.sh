#!/bin/bash
gleam run -m scripts/generate_bindings && gleam format && gleam check && echo "Done & Dusted! 🧹"