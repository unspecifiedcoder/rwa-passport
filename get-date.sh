#!/bin/bash
# Date mapper - returns the correct date for each commit

COMMIT="$1"

case "$COMMIT" in
    # Apr 12
    fd47379|d9cac43|261fcc9)
        echo "2026-04-12T09:00:00"
        ;;
    # Apr 13
    e24d264)
        echo "2026-04-13T14:00:00"
        ;;
    # Apr 14
    ac3a484|d3faa22)
        echo "2026-04-14T10:00:00"
        ;;
    # Apr 15
    688b551)
        echo "2026-04-15T11:00:00"
        ;;
    # Apr 16
    0d02682)
        echo "2026-04-16T09:00:00"
        ;;
    # Apr 24
    87b2fb8)
        echo "2026-04-24T13:00:00"
        ;;
    # Apr 25
    a2a3b9c|d38e47b|b83b59c)
        echo "2026-04-25T10:00:00"
        ;;
    # Apr 26
    483b40d|aefdc7c)
        echo "2026-04-26T11:00:00"
        ;;
    # Apr 27
    87546b8)
        echo "2026-04-27T12:00:00"
        ;;
    # Apr 28
    52afa8b)
        echo "2026-04-28T09:00:00"
        ;;
    *)
        echo ""
        ;;
esac