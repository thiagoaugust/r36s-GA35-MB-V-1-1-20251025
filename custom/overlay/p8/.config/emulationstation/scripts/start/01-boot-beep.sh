#!/bin/bash
# 01-boot-beep.sh — Toca dois bipes quando o EmulationStation termina de iniciar (evento "start").
# O custom_start.sh não serve: o fabricante comentou a chamada dele no emuelec_autostart.sh.
# Obs.: o ES também dispara "start" quando é reiniciado pelo menu.

WAV=/storage/.config/emulationstation/boot-beep.wav
# "playback" é o dmix do asound.conf (não briga com a música do ES); cai para o padrão se falhar
( aplay -q -D plug:playback "$WAV" 2>/dev/null || aplay -q "$WAV" ) &
exit 0
