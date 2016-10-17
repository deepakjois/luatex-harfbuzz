#!/bin/sh
LUATEX_MINIMAL_DIR=$(dirname `which luatex`)
cp ufy.fmt $LUATEX_MINIMAL_DIR/texmf/web2c/
luatex --lua=ufy_pre_init.lua --output-format=pdf --fmt=ufy doc.tex