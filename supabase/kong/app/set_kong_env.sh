#!/bin/bash -e

# Make location of libs configurable
LOCAL='/home/vcap/deps/0/apt/usr/local'

export LD_LIBRARY_PATH=$LOCAL/lib:$LOCAL/lib/lua/5.1/:$LOCAL/openresty/luajit/lib:$LOCAL/openresty/pcre/lib:$LOCAL/openresty/openssl111/lib:$LOCAL/kong/lib:$LD_LIBRARY_PATH
export LUA_PATH="$LOCAL/share/lua/5.1/?.lua;$LOCAL/share/lua/5.1/?/init.lua;$LOCAL/openresty/lualib/?.lua;$LOCAL/openresty/lualib/?/init.lua"
export LUA_CPATH="$LOCAL/lib/lua/5.1/?.so;$LOCAL/openresty/lualib/?.so"
export PATH=$LOCAL/bin:$LOCAL/openresty/nginx/sbin:$LOCAL/openresty/bin:$PATH

export KONG_LUA_PACKAGE_PATH=$LUA_PATH
export KONG_LUA_PACKAGE_CPATH=$LUA_CPATH
