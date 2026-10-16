import json
import os
import wave
import numpy as np
import onnxruntime as ort

MODEL_PATH = r"c:\Users\david\Documents\micgame-3\assets\models\nmp.onnx"
AUDIO_PATH = r"c:\Users\david\Documents\micgame-3\assets\audio\cadence_triads.wav"
CHART_PATH = r"c:\Users\david\Documents\micgame-3\assets\charts\cadence_triads.json"

def read_wav_mono(path):
    with wave.open(path, 'rb') as wf:
        n_channels = wf.getnchannels()
        sampwidth = wf.getsampwidth()
        framerate = wf.getframerate()
        n_frames = wf.getnframes()
        data = wf.readframes(n_frames)
    if sampwidth == 2:
        audio = np.frombuffer(data, dtype=np.int16).astype(np.float32) / 32768.0
    elif sampwidth == 4:
        audio = np.frombuffer(data, dtype=np.float32)
    else:
        raise ValueError(f"Unsupported sampwidth {sampwidth}")
    if n_channels > 1:
        audio = audio.reshape(-1, n_channels).mean(axis=1)
    return audio, framerate

def test_inference():
    audio, sr = read_wav_mono(AUDIO_PATH)
    print(f"Loaded audio: {len(audio)} samples, {len(audio)/sr:.2f}s, sample rate: {sr}")
    
    with open(CHART_PATH, 'r') as f:
        chart = json.load(f)
    print(f"Loaded chart: {chart['title']}, {len(chart['notes'])} notes")
    
    session = ort.InferenceSession(MODEL_PATH)
    
    # Test windowed inference
    # Hop size 256 samples, window 43844 samples
    window_size = 43844
    hop_size = 256 # 1 frame
    # For speed, let's step by say 1024 samples or run full file chunks
    # Note: 1 window = 172 frames (172 * 256 = 44032 samples).
    # If we step by 172 * 256 samples (no overlap for coarse testing):
    print("Testing chunk-based inference across audio...")
    
    # Let's inspect the first 2 seconds (measure 1: chord C3, G3, C4, E4)
    first_chunk = np.zeros(window_size, dtype=np.float32)
    chunk_len = min(window_size, len(audio))
    first_chunk[:chunk_len] = audio[:chunk_len]
    
    input_tensor = first_chunk.reshape(1, window_size, 1)
    outputs = session.run(None, {'serving_default_input_2:0': input_tensor})
    
    # StatefulPartitionedCall:2 is onsets [1, 172, 88]
    # StatefulPartitionedCall:1 is notes [1, 172, 88]
    onsets = outputs[0] if outputs[0].shape == (1, 172, 88) else outputs[1]
    notes = outputs[1] if outputs[1].shape == (1, 172, 88) else outputs[0]
    # Let's check which is which by comparing names
    for i, o in enumerate(session.get_outputs()):
        if o.name == 'StatefulPartitionedCall:2':
            onsets = outputs[i][0] # (172, 88)
        elif o.name == 'StatefulPartitionedCall:1':
            notes = outputs[i][0] # (172, 88)
            
    print(f"Notes shape: {notes.shape}, max note prob: {notes.max():.4f}")
    print(f"Onsets shape: {onsets.shape}, max onset prob: {onsets.max():.4f}")
    
    # Active notes in measure 1 (frames 10 to 60)
    mean_notes = notes[10:60].mean(axis=0) # 88 bins
    active_bins = np.where(mean_notes >= 0.35)[0]
    active_pitches = [b + 21 for b in active_bins]
    print(f"Active pitches in measure 1: {active_pitches}")
    expected = [48, 55, 60, 64]
    print(f"Expected chord pitches: {expected}")
    for p in expected:
        bin_idx = p - 21
        print(f"  Pitch {p}: note_prob={mean_notes[bin_idx]:.3f}, onset_max={onsets[:20, bin_idx].max():.3f}")

if __name__ == "__main__":
    test_inference()
