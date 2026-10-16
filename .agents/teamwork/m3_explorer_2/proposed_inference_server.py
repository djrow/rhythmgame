"""
MicGame-3 WebSocket Audio Inference Server.
Runs Spotify Basic Pitch ONNX model in real-time on CPU via ONNX Runtime and NumPy.
Accepts raw PCM audio streams from Godot 4 game client and emits detected MIDI pitches and onsets.
Zero external dependencies beyond websockets, numpy, and onnxruntime.
"""

import argparse
import asyncio
import json
import logging
import os
import struct
import sys
import time
from typing import Dict, List, Optional, Tuple
import numpy as np

# Ensure local module directory is in path
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
if CURRENT_DIR not in sys.path:
    sys.path.insert(0, CURRENT_DIR)

try:
    from python.basic_pitch_onnx import (
        BasicPitchOnnxRunner,
        AUDIO_SAMPLE_RATE,
        AUDIO_N_SAMPLES,
        resample_to_22050,
    )
except ImportError:
    try:
        from basic_pitch_onnx import (
            BasicPitchOnnxRunner,
            AUDIO_SAMPLE_RATE,
            AUDIO_N_SAMPLES,
            resample_to_22050,
        )
    except ImportError:
        from proposed_basic_pitch_onnx import (
            BasicPitchOnnxRunner,
            AUDIO_SAMPLE_RATE,
            AUDIO_N_SAMPLES,
            resample_to_22050,
        )

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] [%(levelname)s] [InferenceServer] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("InferenceServer")


class ClientSession:
    """Encapsulates per-connection audio buffer and stream state."""

    def __init__(
        self,
        runner: BasicPitchOnnxRunner,
        sample_rate: int = AUDIO_SAMPLE_RATE,
        pcm_format: str = "float32",
        response_format: str = "json",
    ):
        self.runner = runner
        self.sample_rate = sample_rate
        self.pcm_format = pcm_format  # "float32" or "int16"
        self.response_format = response_format  # "json" or "binary"
        self.ring_buffer = np.zeros(AUDIO_N_SAMPLES, dtype=np.float32)
        self.last_onset_time: Dict[int, float] = {p: -999.0 for p in range(21, 109)}
        self.start_time = time.perf_counter()
        self.total_samples_received = 0
        self.inference_count = 0

    def reset(self) -> None:
        self.ring_buffer.fill(0)
        self.last_onset_time = {p: -999.0 for p in range(21, 109)}
        self.start_time = time.perf_counter()
        self.total_samples_received = 0

    def process_pcm_bytes(self, raw_bytes: bytes) -> Tuple[List[int], List[int], Dict[str, float], float]:
        """
        Parses raw PCM bytes, handles resampling, slides ring buffer, and runs model forward pass.
        Returns: (active_pitches, recent_onsets, confidence_dict, inference_latency_ms)
        """
        # Decode PCM bytes
        if self.pcm_format == "int16":
            samples = np.frombuffer(raw_bytes, dtype=np.int16).astype(np.float32) / 32768.0
        else:
            # Default float32 little-endian
            samples = np.frombuffer(raw_bytes, dtype=np.float32)

        if len(samples) == 0:
            return [], [], {}, 0.0

        # Resample to 22,050 Hz if needed
        if self.sample_rate != AUDIO_SAMPLE_RATE:
            samples_22k = resample_to_22050(samples, self.sample_rate)
        else:
            samples_22k = samples

        n_new = len(samples_22k)
        if n_new >= AUDIO_N_SAMPLES:
            self.ring_buffer[:] = samples_22k[-AUDIO_N_SAMPLES:]
        else:
            self.ring_buffer[:-n_new] = self.ring_buffer[n_new:]
            self.ring_buffer[-n_new:] = samples_22k

        self.total_samples_received += len(samples)
        current_time_sec = time.perf_counter() - self.start_time

        # Run ONNX inference
        t0 = time.perf_counter()
        notes, onsets = self.runner.predict_window(self.ring_buffer)
        t_infer = (time.perf_counter() - t0) * 1000.0
        self.inference_count += 1

        # Receptive field analysis: frames 158..167 (last ~70ms preceding boundary edge)
        rec_notes = notes[158:168]
        rec_onsets = onsets[158:168]

        max_notes = rec_notes.max(axis=0)
        max_onsets = rec_onsets.max(axis=0)

        active_pitches: List[int] = []
        recent_onsets: List[int] = []
        confidences: Dict[str, float] = {}

        for b in range(88):
            pitch = b + 21
            prob = float(max_notes[b])
            ons = float(max_onsets[b])

            if prob >= self.runner.note_threshold:
                active_pitches.append(pitch)
                confidences[str(pitch)] = round(prob, 3)

            if ons >= self.runner.onset_threshold:
                if (current_time_sec - self.last_onset_time[pitch]) >= 0.120:
                    recent_onsets.append(pitch)
                    self.last_onset_time[pitch] = current_time_sec

        return active_pitches, recent_onsets, confidences, t_infer


async def handle_connection(websocket, runner: BasicPitchOnnxRunner, default_sr: int):
    """Handles an individual WebSocket client connection."""
    client_addr = getattr(websocket, "remote_address", "client")
    logger.info(f"Client connected from {client_addr}")

    session = ClientSession(runner, sample_rate=default_sr)

    try:
        async for message in websocket:
            if isinstance(message, str):
                # Text/JSON control command
                try:
                    cmd_data = json.loads(message)
                except json.JSONDecodeError:
                    logger.warning(f"Invalid JSON received from {client_addr}: {message[:50]}")
                    continue

                cmd = cmd_data.get("cmd", "")
                if cmd == "config":
                    if "sample_rate" in cmd_data:
                        session.sample_rate = int(cmd_data["sample_rate"])
                    if "pcm_format" in cmd_data:
                        session.pcm_format = str(cmd_data["pcm_format"])
                    if "response_format" in cmd_data:
                        session.response_format = str(cmd_data["response_format"])
                    if "note_thresh" in cmd_data:
                        runner.note_threshold = float(cmd_data["note_thresh"])
                    if "onset_thresh" in cmd_data:
                        runner.onset_threshold = float(cmd_data["onset_thresh"])

                    logger.info(
                        f"Updated config for {client_addr}: sr={session.sample_rate}, "
                        f"fmt={session.pcm_format}, resp={session.response_format}, "
                        f"note_th={runner.note_threshold}, onset_th={runner.onset_threshold}"
                    )
                    await websocket.send(json.dumps({
                        "type": "config_ack",
                        "status": "ok",
                        "sample_rate": session.sample_rate,
                        "pcm_format": session.pcm_format,
                        "response_format": session.response_format,
                    }))

                elif cmd == "reset":
                    session.reset()
                    logger.info(f"Buffer reset for {client_addr}")
                    await websocket.send(json.dumps({"type": "reset_ack", "status": "ok"}))

                elif cmd == "ping":
                    await websocket.send(json.dumps({
                        "type": "pong",
                        "server_time": time.time(),
                    }))

            elif isinstance(message, bytes):
                # Raw PCM audio chunk
                active, onsets, confs, latency_ms = session.process_pcm_bytes(message)
                timestamp = round(time.perf_counter() - session.start_time, 3)

                if session.response_format == "binary":
                    # Compact binary encoding matching Godot proposed_websocket_driver.gd:
                    # Byte 0: N (number of active pitches)
                    # Bytes 1..N: active pitch bytes
                    # Byte N+1: M (number of onsets)
                    # Bytes N+2..N+1+M: onset pitch bytes
                    pkt = bytearray()
                    pkt.append(len(active))
                    for p in active:
                        pkt.append(int(p) & 0xFF)
                    pkt.append(len(onsets))
                    for o in onsets:
                        pkt.append(int(o) & 0xFF)
                    await websocket.send(bytes(pkt))
                else:
                    # JSON response schema matching Godot proposed_websocket_driver.gd:
                    # {"type":"pitches","pitches":[...],"onsets":[...],"timestamp":...,"confidence":{...}}
                    resp = {
                        "type": "pitches",
                        "pitches": active,
                        "onsets": onsets,
                        "timestamp": timestamp,
                        "confidence": confs,
                        "latency_ms": round(latency_ms, 2),
                    }
                    await websocket.send(json.dumps(resp))

    except Exception as e:
        logger.warning(f"Connection exception from {client_addr}: {e}")
    finally:
        logger.info(f"Client disconnected: {client_addr}")


def start_server(
    model_path: str,
    host: str = "127.0.0.1",
    port: int = 8765,
    sample_rate: int = AUDIO_SAMPLE_RATE,
    note_thresh: float = 0.40,
    onset_thresh: float = 0.45,
):
    """Starts the asyncio WebSocket server."""
    logger.info(f"Loading Basic Pitch ONNX model from {model_path}...")
    runner = BasicPitchOnnxRunner(
        model_path=model_path,
        note_threshold=note_thresh,
        onset_threshold=onset_thresh,
    )
    logger.info("ONNX model loaded successfully.")

    # Warm-up inference
    dummy = np.zeros(AUDIO_N_SAMPLES, dtype=np.float32)
    t0 = time.perf_counter()
    runner.predict_window(dummy)
    warmup_ms = (time.perf_counter() - t0) * 1000.0
    logger.info(f"Model warm-up completed in {warmup_ms:.2f} ms.")

    import websockets

    async def main_loop():
        # Start WebSocket server
        server = await websockets.serve(
            lambda ws: handle_connection(ws, runner, sample_rate),
            host,
            port,
        )
        logger.info(f"WebSocket inference server listening on ws://{host}:{port}")
        logger.info(f"Default config: sample_rate={sample_rate} Hz, note_th={note_thresh}, onset_th={onset_thresh}")
        await asyncio.Future()  # run forever

    try:
        asyncio.run(main_loop())
    except KeyboardInterrupt:
        logger.info("Server shutting down cleanly on SIGINT.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="MicGame-3 Basic Pitch WebSocket Inference Server")
    parser.add_argument("--model-path", type=str, default=r"c:\Users\david\Documents\micgame-3\assets\models\nmp.onnx", help="Path to nmp.onnx")
    parser.add_argument("--host", type=str, default="127.0.0.1", help="Host interface to bind")
    parser.add_argument("--port", type=int, default=8765, help="Port to bind")
    parser.add_argument("--sample-rate", type=int, default=22050, help="Default audio sample rate")
    parser.add_argument("--note-thresh", type=float, default=0.40, help="Note probability threshold (0.0 to 1.0)")
    parser.add_argument("--onset-thresh", type=float, default=0.45, help="Onset probability threshold (0.0 to 1.0)")
    args = parser.parse_args()

    start_server(
        model_path=args.model_path,
        host=args.host,
        port=args.port,
        sample_rate=args.sample_rate,
        note_thresh=args.note_thresh,
        onset_thresh=args.onset_thresh,
    )
