#!/bin/bash

set -eu

cd $(dirname "$0")

mkdir -p dist
npm run build
cp build/index.js dist/index.js
