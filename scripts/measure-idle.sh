#!/bin/zsh
# Mede o Trincano ocioso: 6 amostras de 10 s de CPU/memoria/wakeups/threads + footprint + RSS.
# Uso: scripts/measure-idle.sh [amostras=6]
PID=$(pgrep -x Trincano) || { echo "Trincano nao esta rodando"; exit 1; }
echo "PID $PID, uptime $(ps -o etime= -p $PID | tr -d ' ')"
top -l "${1:-6}" -s 10 -pid "$PID" -stats pid,cpu,mem,idlew,power,threads | grep -E "^$PID"
footprint "$PID" | grep phys_footprint
echo "RSS KB: $(ps -o rss= -p $PID | tr -d ' ')"
