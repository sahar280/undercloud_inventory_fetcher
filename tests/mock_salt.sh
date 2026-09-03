#!/usr/bin/env bash
set -euo pipefail

remote_command=${3:-}

case "$remote_command" in
  *system-serial-number*) first='SAMPLE001'; second='SAMPLE002' ;;
  *bios-version*) first='2.8.0'; second='2.8.0' ;;
  *'mc info'*) first='4.10'; second='4.10' ;;
  *'lan print'*) first='198.51.100.10'; second='198.51.100.11' ;;
  *br-all*) first='203.0.113.10/24'; second='203.0.113.11/24' ;;
  *) first='192.0.2.10/24'; second='192.0.2.11/24' ;;
esac

printf 'compute-0:\n    VALUE=%s\ncompute-1:\n    VALUE=%s\n' "$first" "$second"
