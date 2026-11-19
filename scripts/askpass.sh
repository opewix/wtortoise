#!/bin/sh
# git и ssh зовут эту программу, когда им нужен пароль или подтверждение; вопрос показывает WTortoise.
# Имя и пароль, введённые в окне входа WTortoise, приходят в окружении — второй раз не спрашиваем.
case "$1" in
  Username*) if [ -n "${WTORTOISE_USERNAME+x}" ]; then printf '%s\n' "$WTORTOISE_USERNAME"; exit 0; fi ;;
  Password*) if [ -n "${WTORTOISE_PASSWORD+x}" ]; then printf '%s\n' "$WTORTOISE_PASSWORD"; exit 0; fi ;;
esac
exec "$(dirname "$0")/../MacOS/WTortoise" -askpass "$1"
