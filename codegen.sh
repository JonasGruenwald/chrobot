#!/bin/bash
gleam run -m chrobot/internal/generate_bindings && gleam format && gleam check && echo "Done & Dusted! 🧹"