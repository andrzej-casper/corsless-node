#!/usr/bin/env bash
set -e

mitmproxy -s ./cors.py --mode reverse:http://85.114.132.133:7777 --listen-host localhost -p 7777
