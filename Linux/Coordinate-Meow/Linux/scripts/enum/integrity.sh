#!/bin/sh
# KaliPatriot | TTU CCDC | Landon Byrge

if command -v debsums >/dev/null 2>&1; then
    debsums -ca
fi

if command -v rpm >/dev/null 2>&1; then
    rpm -Va
fi