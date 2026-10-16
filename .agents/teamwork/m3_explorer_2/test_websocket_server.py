import asyncio
import json
import os
import subprocess
import sys
import time
import numpy as np
import websockets

SERVER_SCRIPT = os.path.join(os.path.dirname(__file__), "proposed_inference_server.py")
MODEL_PATH = r"c:\Users\david\Documents\micgame-3\assets\models\nmp.onnx"
HOST = "127.0.0.1"
PORT = 8799  # Use custom port for test to avoid conflicts

async def test_client():
    uri = f"ws://{HOST}:{PORT}"
    print(f"[Client] Connecting to {uri}...")
    async with websockets.connect(uri) as ws:
        print("[Client] Connected!")
        
        # 1. Test ping
        await ws.send(json.dumps({"cmd": "ping"}))
        resp = await ws.recv()
        data = json.loads(resp)
        print(f"[Client] Ping response: {data}")
        assert data.get("type") == "pong"
        
        # 2. Test config
        await ws.send(json.dumps({
            "cmd": "config",
            "sample_rate": 22050,
            "pcm_format": "float32",
            "note_thresh": 0.40,
            "onset_thresh": 0.45
        }))
        resp = await ws.recv()
        data = json.loads(resp)
        print(f"[Client] Config response: {data}")
        assert data.get("type") == "config_ack"
        
        # 3. Stream synthetic C4 tone (261.63 Hz, MIDI 60)
        sr = 22050
        duration_sec = 0.5
        t = np.linspace(0, duration_sec, int(sr * duration_sec), endpoint=False, dtype=np.float32)
        f0 = 440.0 * (2.0 ** ((60 - 69) / 12.0)) # C4 ~261.63 Hz
        tone = 0.8 * np.sin(2 * np.pi * f0 * t).astype(np.float32)
        
        # Send in 1024-sample chunks
        chunk_size = 1024
        all_pitches = set()
        all_onsets = set()
        
        for i in range(0, len(tone), chunk_size):
            chunk = tone[i:i + chunk_size]
            raw_bytes = chunk.tobytes()
            await ws.send(raw_bytes)
            
            resp = await ws.recv()
            data = json.loads(resp)
            print(f"[Client] Chunk {i//chunk_size} resp: pitches={data.get('pitches')}, onsets={data.get('onsets')}, latency={data.get('latency_ms')}ms")
            for p in data.get("pitches", []):
                all_pitches.add(p)
            for o in data.get("onsets", []):
                all_onsets.add(o)
                
        print(f"[Client] All detected pitches: {all_pitches}")
        print(f"[Client] All detected onsets: {all_onsets}")
        assert 60 in all_pitches, f"Expected MIDI 60 (C4) in active pitches, got {all_pitches}"
        print("[Client] E2E WebSocket test PASSED successfully!")

def main():
    cmd = [
        sys.executable, SERVER_SCRIPT,
        "--model-path", MODEL_PATH,
        "--host", HOST,
        "--port", str(PORT)
    ]
    print(f"Starting server: {' '.join(cmd)}")
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    
    # Wait for server to bind
    time.sleep(2.0)
    try:
        asyncio.run(test_client())
    finally:
        print("Terminating server...")
        proc.terminate()
        try:
            out, _ = proc.communicate(timeout=3)
            print("Server stdout:\n" + out)
        except Exception:
            proc.kill()

if __name__ == "__main__":
    main()
