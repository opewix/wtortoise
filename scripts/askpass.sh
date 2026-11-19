#!/bin/sh
# git и ssh зовут эту программу, когда им нужен пароль или подтверждение; вопрос показывает WTortoise.
exec "$(dirname "$0")/../MacOS/WTortoise" -askpass "$1"
