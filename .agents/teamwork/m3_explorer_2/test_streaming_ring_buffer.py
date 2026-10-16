import json
import os
import wave
import numpy as np
import onnxruntime as ort

MODEL_PATH = r"c:\Users\david\Documents\micgame-3\assets\models\nmp.onnx"
AUDIO_DIR = r"c:\Users\david\Documents\micgame-3\assets\audio"
CHARTS_DIR = r"c:\Users\david\Documents\micgame-3\assets\charts"

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

class StreamingInferenceEngine:
    def __init__(self, model_path, note_thresh=0.45, onset_thresh=0.50):
        self.session = ort.InferenceSession(model_path)
        self.input_name = self.session.get_inputs()[0].name
        
        # Determine output names
        self.onset_name = None
        self.note_name = None
        for o in self.session.get_outputs():
            if o.name == 'StatefulPartitionedCall:2':
                self.onset_name = o.name
            elif o.name == 'StatefulPartitionedCall:1':
                self.note_name = o.name
        if not self.onset_name or not self.note_name:
            self.onset_name = self.session.get_outputs()[0].name
            self.note_name = self.session.get_outputs()[1].name
            
        self.buffer_size = 43844
        self.ring_buffer = np.zeros(self.buffer_size, dtype=np.float32)
        self.note_thresh = note_thresh
        self.onset_thresh = onset_thresh
        
        # Debounce tracking for onsets: frames since last onset per pitch
        self.last_onset_time = {p: -999.0 for p in range(21, 109)}
        self.active_pitches = set()
        
    def reset(self):
        self.ring_buffer.fill(0)
        self.last_onset_time = {p: -999.0 for p in range(21, 109)}
        self.active_pitches.clear()
        
    def push_audio_chunk(self, chunk_pcm_float32, current_time_sec=0.0):
        """
        Pushes a new chunk of 22050 Hz float32 audio into the ring buffer,
        runs inference, and returns active pitches and newly detected onsets.
        """
        chunk_len = len(chunk_pcm_float32)
        if chunk_len == 0:
            return [], [], {}
            
        if chunk_len >= self.buffer_size:
            self.ring_buffer[:] = chunk_pcm_float32[-self.buffer_size:]
        else:
            self.ring_buffer[:-chunk_len] = self.ring_buffer[chunk_len:]
            self.ring_buffer[-chunk_len:] = chunk_pcm_float32
            
        # Inference
        input_tensor = self.ring_buffer.reshape(1, self.buffer_size, 1)
        outs = self.session.run(None, {self.input_name: input_tensor})
        out_dict = {o.name: outs[i] for i, o in enumerate(self.session.get_outputs())}
        
        onsets_out = out_dict[self.onset_name][0] # (172, 88)
        notes_out = out_dict[self.note_name][0]   # (172, 88)
        
        # The receptive field for the latest audio (at end of buffer):
        # Frame 171 is the last frame.
        # Let's inspect the latest 6 frames: frames 166..171 (approx 70 ms)
        latest_notes = notes_out[165:172] # (7, 88)
        latest_onsets = onsets_out[165:172] # (7, 88)
        
        max_notes = latest_notes.max(axis=0) # 88
        max_onsets = latest_onsets.max(axis=0) # 88
        
        detected_active = []
        detected_onsets = []
        confidences = {}
        
        for b in range(88):
            pitch = b + 21
            prob = float(max_notes[b])
            ons = float(max_onsets[b])
            
            if prob >= self.note_thresh:
                detected_active.append(pitch)
                confidences[pitch] = round(prob, 3)
                
            # Onset detection:
            # Check if onset peak in latest frames >= onset_thresh
            # and debounce at least 100ms since last onset of this pitch
            if ons >= self.onset_thresh:
                if (current_time_sec - self.last_onset_time[pitch]) >= 0.12:
                    detected_onsets.append(pitch)
                    self.last_onset_time[pitch] = current_time_sec
                    
        return detected_active, detected_onsets, confidences

def test_streaming(wav_name, json_name, chunk_size=1024):
    wav_path = os.path.join(AUDIO_DIR, wav_name)
    json_path = os.path.join(CHARTS_DIR, json_name)
    
    audio, sr = read_wav_mono(wav_path)
    with open(json_path, 'r') as f:
        chart = json.load(f)
        
    engine = StreamingInferenceEngine(MODEL_PATH, note_thresh=0.45, onset_thresh=0.50)
    
    all_triggered_onsets = [] # list of (pitch, time_sec)
    
    total_samples = len(audio)
    for start_idx in range(0, total_samples, chunk_size):
        chunk = audio[start_idx:min(start_idx + chunk_size, total_samples)]
        current_time = start_idx / sr
        active, onsets, confs = engine.push_audio_chunk(chunk, current_time)
        for p in onsets:
            all_triggered_onsets.append({"pitch": p, "time_sec": round(current_time, 3), "confidence": confs.get(p, 0.0)})
            
    # Evaluate against chart notes
    gt_notes = chart["notes"]
    gt_matched = [False] * len(gt_notes)
    det_matched = [False] * len(all_triggered_onsets)
    
    onset_tolerance = 0.15 # 150ms window
    for i, d in enumerate(all_triggered_onsets):
        for j, g in enumerate(gt_notes):
            if gt_matched[j]:
                continue
            pitch_match = (d["pitch"] == g["pitch_midi"])
            onset_match = (abs(d["time_sec"] - g["time_sec"]) <= onset_tolerance)
            if pitch_match and onset_match:
                gt_matched[j] = True
                det_matched[i] = True
                break
                
    tp = sum(det_matched)
    fp = len(all_triggered_onsets) - tp
    fn = len(gt_notes) - sum(gt_matched)
    
    precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0.0
    
    print(f"\n--- Streaming: {chart['title']} (chunk={chunk_size} samples / {chunk_size/sr*1000:.1f}ms) ---")
    print(f"Ground Truth: {len(gt_notes)}, Detected Onsets: {len(all_triggered_onsets)}")
    print(f"TP: {tp}, FP: {fp}, FN: {fn}")
    print(f"Precision: {precision*100:.1f}%, Recall: {recall*100:.1f}%, F1: {f1*100:.1f}%")
    return f1

def main():
    pieces = [
        ("ode_to_joy.wav", "ode_to_joy.json"),
        ("bach_minuet.wav", "bach_minuet.json"),
        ("cadence_triads.wav", "cadence_triads.json")
    ]
    for w, j in pieces:
        test_streaming(w, j, chunk_size=1024)

if __name__ == "__main__":
    main()
