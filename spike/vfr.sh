source ./pattern.sh
ffmpeg -hide_banner -loglevel error -y -filter_complex "$(pattern 640 360 30 6),select='not(mod(n\,3))+not(mod(n\,7))'[v]" -map "[v]" -fps_mode vfr -c:v libx264 -pix_fmt yuv420p h264_vfr_noaudio.mp4
