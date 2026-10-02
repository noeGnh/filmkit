# pattern W H RATE DURATION: displayed-orientation test pattern (4 quadrants: red TL, green TR,
# blue BL, white BR) with a central band whose gray level encodes t / duration.
pattern(){ W=$1; H=$2; R=$3; D=$4; HW=$((W/2)); HH=$((H/2));
echo "color=red:s=${HW}x${HH}:r=${R}:d=${D}[tl];color=0x00ff00:s=${HW}x${HH}:r=${R}:d=${D}[tr];color=blue:s=${HW}x${HH}:r=${R}:d=${D}[bl];color=white:s=${HW}x${HH}:r=${R}:d=${D}[br];[tl][tr]hstack[top];[bl][br]hstack[bot];[top][bot]vstack,format=yuv420p,geq=lum='if(between(Y,H*0.45,H*0.55),255*T/${D},lum(X,Y))':cb='if(between(Y,H*0.45,H*0.55),128,cb(X,Y))':cr='if(between(Y,H*0.45,H*0.55),128,cr(X,Y))'"; }
q="-hide_banner -loglevel error -y"
aud(){ echo "-f lavfi -i sine=frequency=440:duration=$1"; }
# 1. H.264 landscape with audio
ffmpeg $q $(aud 6) -filter_complex "$(pattern 640 360 30 6)[v]" -map "[v]" -map 0:a -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest h264_landscape.mp4
# 2. HEVC landscape with audio
ffmpeg $q $(aud 6) -filter_complex "$(pattern 640 360 30 6)[v]" -map "[v]" -map 0:a -c:v libx265 -tag:v hvc1 -pix_fmt yuv420p -c:a aac -shortest hevc_landscape.mp4
# 3/4. Portrait as phones record it: frames stored landscape + rotation tag. The displayed
# pattern is 360x640; stored frames are its transpose, display rotation compensates.
ffmpeg $q $(aud 6) -filter_complex "$(pattern 360 640 30 6),transpose=2[v]" -map "[v]" -map 0:a -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest raw_t2.mp4
ffmpeg $q -display_rotation 270 -i raw_t2.mp4 -c copy h264_rot90.mp4
ffmpeg $q $(aud 6) -filter_complex "$(pattern 360 640 30 6),transpose=1[v]" -map "[v]" -map 0:a -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest raw_t1.mp4
ffmpeg $q -display_rotation 90 -i raw_t1.mp4 -c copy h264_rot270.mp4
rm -f raw_t1.mp4 raw_t2.mp4

# 6. 4K 60 fps
ffmpeg $q $(aud 4) -filter_complex "$(pattern 3840 2160 60 4)[v]" -map "[v]" -map 0:a -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac -shortest h264_4k60.mp4
# 7. HDR10: HEVC Main10, BT.2020 / PQ tags
ffmpeg $q $(aud 6) -filter_complex "$(pattern 640 360 30 6)[v]" -map "[v]" -map 0:a -c:v libx265 -tag:v hvc1 -pix_fmt yuv420p10le -x265-params "colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc" -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc -c:a aac -shortest hevc_hdr10.mp4
# 5. Variable frame rate: irregular frame intervals, original timestamps kept, no audio
ffmpeg $q -filter_complex "$(pattern 640 360 30 6),select='not(mod(n\,3))+not(mod(n\,7))'[v]" -map "[v]" -fps_mode vfr -c:v libx264 -pix_fmt yuv420p h264_vfr_noaudio.mp4
