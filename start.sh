#!/bin/bash
mkdir -p stream/v0 stream/v1

python3 -c '
import http.server
import socketserver
import os

PORT = int(os.environ.get("PORT", 8080))
DIRECTORY = "stream"

class HLSHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)
        
    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        super().end_headers()
        
    def guess_type(self, path):
        if path.endswith(".m3u8"):
            return "application/vnd.apple.mpegurl"
        elif path.endswith(".ts"):
            return "video/mp2t"
        return super().guess_type(path)

with socketserver.TCPServer(("0.0.0.0", PORT), HLSHTTPRequestHandler) as httpd:
    httpd.serve_forever()
' &

while true; do
    STREAM_URL=$(python3 -c "
import urllib.request
try:
    req_obj = urllib.request.Request(
        'https://tight-firefly-ecdd.poonamchouhan076.workers.dev/', 
        headers={'User-Agent': 'Mozilla/5.0'}
    )
    req = urllib.request.urlopen(req_obj)
    lines = req.read().decode('utf-8').splitlines()
    for i in range(len(lines)):
        if 'sony max' in lines[i].lower():
            for j in range(i+1, min(i+10, len(lines))):
                if lines[j].strip().startswith('http'):
                    print(lines[j].strip())
                    exit()
    for line in lines:
        if line.strip().startswith('http'):
            print(line.strip())
            break
except Exception:
    pass
")

    if [ -z "$STREAM_URL" ]; then
        sleep 5
        continue
    fi

    ffmpeg -reconnect 1 -reconnect_streamed 1 -reconnect_delay_max 5 \
    -i "$STREAM_URL" \
    -filter_complex '[0:v]drawtext=text="PRT":fontcolor=red:fontsize=32:x=20:y=20,drawtext=text="STREAM":fontcolor=yellow:fontsize=32:x=100:y=20,split=2[v1][v2];[v1]scale=854:480[v1out];[v2]scale=1280:720[v2out]' \
    -map '[v1out]' -c:v:0 libx264 -preset ultrafast -b:v:0 400k -maxrate 400k -bufsize 800k -g 100 \
    -map '[v2out]' -c:v:1 libx264 -preset veryfast -b:v:1 900k -maxrate 900k -bufsize 1500k -g 100 \
    -map 0:a:0 -c:a:0 aac -b:a:0 96k \
    -map 0:a:0 -c:a:1 aac -b:a:1 128k \
    -f hls \
    -hls_time 4 \
    -hls_list_size 10 \
    -hls_flags delete_segments+append_list+independent_segments \
    -var_stream_map 'v:0,a:0 v:1,a:1' \
    -master_pl_name master.m3u8 \
    -hls_segment_filename 'stream/v%v/seg_%03d.ts' \
    stream/v%v/index.m3u8

    sleep 5
done
