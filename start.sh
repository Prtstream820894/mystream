#!/bin/bash
mkdir -p stream/v0 stream/v1

# HLS Local HTTP Server background mein chalane ke liye
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

# Continuous Loop jo link expire hone par naya link fetch karega
while true; do
    echo "==> Crichd se naya stream link dhoond rahe hain..."
    
    # Python script jo tera multi-step logic execute karegi
    read STREAM_URL EMBED_REF < <(python3 -c '
import urllib.request
import re

try:
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Referer": "https://crichdsee.st/"
    }
    
    # Step 1: Crichd player page kholo
    player_url = "https://crichdsee.st/player.php?id=starsp3"
    req = urllib.request.Request(player_url, headers=headers)
    html = urllib.request.urlopen(req, timeout=10).read().decode("utf-8")
    
    # Step 2: Embed/Iframe nikalo
    iframes = re.findall(r"<iframe[^>]+src=[\"'\']([^\"'\']+)[\"'\']", html)
    for iframe in iframes:
        if not iframe.startswith("http"):
            if iframe.startswith("//"):
                iframe = "https:" + iframe
            else:
                continue
                
        # Step 3: Embed page ko crichd referer ke sath kholo
        embed_headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Referer": "https://crichdsee.st/"
        }
        embed_req = urllib.request.Request(iframe, headers=embed_headers)
        try:
            embed_html = urllib.request.urlopen(embed_req, timeout=10).read().decode("utf-8")
        except:
            continue
            
        # Step 4: Embed ke andar .m3u8 ya inner script/fid link dhoondo
        m3u8s = re.findall(r"https?://[^\s<>\"\']+?\.m3u8[^\s<>\"\']*", embed_html)
        if m3u8s:
            print(m3u8s[0] + " " + iframe)
            exit()
            
        # Agar direct nahi mila, toh check karo agar koi script ke andar url ya fid hai
        inner_iframes = re.findall(r"src=[\"'\'](https?://[^\"'\']+)[\"'\']", embed_html)
        for inner in inner_iframes:
            try:
                inner_req = urllib.request.Request(inner, headers={"User-Agent": "Mozilla/5.0", "Referer": iframe})
                inner_html = urllib.request.urlopen(inner_req, timeout=5).read().decode("utf-8")
                inner_m3u8s = re.findall(r"https?://[^\s<>\"\']+?\.m3u8[^\s<>\"\']*", inner_html)
                if inner_m3u8s:
                    print(inner_m3u8s[0] + " " + inner)
                    exit()
            except:
                continue
except Exception as e:
    pass
')

    if [ -z "$STREAM_URL" ]; then
        echo "Link nahi mila, 15 second baad dobara koshish kar rahe hain..."
        sleep 15
        continue
    fi

    echo "==> Mil gaya Link: $STREAM_URL"
    echo "==> Embed Referer: $EMBED_REF"

    # Step 5 & 6: Real embed referer ke sath FFmpeg chalao, aur agar link tuta/expire hua toh loop dobara naya link utha lega
    ffmpeg -reconnect 1 -reconnect_streamed 1 -reconnect_delay_max 5 \
    -user_agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
    -headers "Referer: $EMBED_REF$'\r\n'Origin: https://crichdsee.st$'\r\n'" \
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
    -master_pl_name stream/master.m3u8 \
    -hls_segment_filename 'stream/v%v/seg_%03d.ts' \
    stream/v%v/index.m3u8

    echo "Stream band hui ya link expire hua, naya link fetch kar rahe hain..."
    sleep 5
done
