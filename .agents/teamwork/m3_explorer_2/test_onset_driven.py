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

def run_onset_driven_transcription(audio, sample_rate, session, onset_thresh=0.45, frame_thresh=0.35, min_dur_sec=0.08):
    """
    Onset-driven note extraction:
    Notes are initiated by local peaks in onsets >= onset_thresh.
    They sustain while notes >= frame_thresh.
    Subsequent onset peaks on the same pitch segment a new note.
    """
    window_samples = 43844
    total_samples = len(audio)
    fps = 22050.0 / 256.0
    
    n_total_frames = int(np.ceil(total_samples / 256)) + 172
    full_notes = np.zeros((n_total_frames, 88), dtype=np.float32)
    full_onsets = np.zeros((n_total_frames, 88), dtype=np.float32)
    counts = np.zeros((n_total_frames, 1), dtype=np.float32)
    
    step = 22016 # 86 frames
    
    for start_sample in range(0, total_samples, step):
        chunk = np.zeros(window_samples, dtype=np.float32)
        end_sample = min(start_sample + window_samples, total_samples)
        valid_len = end_sample - start_sample
        chunk[:valid_len] = audio[start_sample:end_sample]
        
        inp = chunk.reshape(1, window_samples, 1)
        outs = session.run(None, {'serving_default_input_2:0': inp})
        
        cur_onsets = outs[0] if session.get_outputs()[0].name == 'StatefulPartitionedCall:2' else outs[1]
        cur_notes = outs[1] if session.get_outputs()[1].name == 'StatefulPartitionedCall:1' else outs[0]
        cur_onsets = cur_onsets[0]
        cur_notes = cur_notes[0]
        
        start_frame = start_sample // 256
        end_frame = start_frame + 172
        
        full_notes[start_frame:end_frame] += cur_notes
        full_onsets[start_frame:end_frame] = np.maximum(full_onsets[start_frame:end_frame], cur_onsets)
        counts[start_frame:end_frame] += 1.0
        
    counts[counts == 0] = 1.0
    full_notes /= counts
    
    # Trim to valid length
    valid_frames = int(np.ceil(total_samples / 256))
    full_notes = full_notes[:valid_frames]
    full_onsets = full_onsets[:valid_frames]
    
    detected_notes = []
    
    # Process each pitch
    for b in range(88):
        pitch = b + 21
        ons = full_onsets[:, b]
        frames = full_notes[:, b]
        
        # 1. Detect onset peak frames: local max in a 3-frame neighborhood >= onset_thresh
        onset_peaks = []
        for f in range(len(ons)):
            if ons[f] >= onset_thresh:
                is_local_max = True
                if f > 0 and ons[f] < ons[f - 1]:
                    is_local_max = False
                if f < len(ons) - 1 and ons[f] < ons[f + 1]:
                    is_local_max = False
                if is_local_max:
                    onset_peaks.append(f)
                    
        # 2. For each onset peak, trace duration forward while frames >= frame_thresh
        for i, start_f in enumerate(onset_peaks):
            # Limit duration up to the next onset peak for this pitch
            next_onset_f = onset_peaks[i + 1] if i + 1 < len(onset_peaks) else len(frames)
            
            # Trace end frame
            end_f = start_f + 1
            while end_f < next_onset_f and end_f < len(frames) and frames[end_f] >= frame_thresh:
                end_f += 1
                
            dur_sec = (end_f - start_f) / fps
            onset_sec = start_f / fps
            
            if dur_sec >= min_dur_sec:
                mean_conf = float(frames[start_f:end_f].mean())
                detected_notes.append({
                    "pitch": pitch,
                    "onset_sec": round(onset_sec, 3),
                    "duration_sec": round(dur_sec, 3),
                    "confidence": round(mean_conf, 3),
                    "onset_prob": round(float(ons[start_f]), 3)
                })
                
    detected_notes.sort(key=lambda x: x["onset_sec"])
    return detected_notes

def evaluate_metrics(detected, ground_truth, onset_tolerance=0.15, pitch_tolerance=0):
    gt_matched = [False] * len(ground_truth)
    det_matched = [False] * len(detected)
    
    for i, d in enumerate(detected):
        for j, g in enumerate(ground_truth):
            if gt_matched[j]:
                continue
            pitch_match = (abs(d["pitch"] - g["pitch_midi"]) <= pitch_tolerance)
            onset_match = (abs(d["onset_sec"] - g["time_sec"]) <= onset_tolerance)
            if pitch_match and onset_match:
                gt_matched[j] = True
                det_matched[i] = True
                break
                
    tp = sum(det_matched)
    fp = len(detected) - tp
    fn = len(ground_truth) - sum(gt_matched)
    
    precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0.0
    return {
        "tp": tp, "fp": fp, "fn": fn,
        "precision": precision, "recall": recall, "f1": f1
    }

def main():
    session = ort.InferenceSession(MODEL_PATH)
    
    pieces = [
        ("ode_to_joy.wav", "ode_to_joy.json"),
        ("bach_minuet.wav", "bach_minuet.json"),
        ("cadence_triads.wav", "cadence_triads.json")
    ]
    
    for wav_name, json_name in pieces:
        wav_path = os.path.join(AUDIO_DIR, wav_name)
        json_path = os.path.join(CHARTS_DIR, json_name)
        
        audio, sr = read_wav_mono(wav_path)
        with open(json_path, 'r') as f:
            chart = json.load(f)
            
        detected = run_onset_driven_transcription(audio, sr, session, onset_thresh=0.45, frame_thresh=0.35, min_dur_sec=0.08)
        metrics = evaluate_metrics(detected, chart["notes"], onset_tolerance=0.15)
        
        print(f"\n--- {chart['title']} ({wav_name}) ---")
        print(f"Ground Truth Notes: {len(chart['notes'])}, Detected: {len(detected)}")
        print(f"TP: {metrics['tp']}, FP: {metrics['fp']}, FN: {metrics['fn']}")
        print(f"Precision: {metrics['precision']*100:.1f}%, Recall: {metrics['recall']*100:.1f}%, F1: {metrics['f1']*100:.1f}%")
        for n in detected:
            print(f"  Pitch: {n['pitch']}, Onset: {n['onset_sec']}s, Dur: {n['duration_sec']}s, Conf: {n['confidence']}, OnsetProb: {n['onset_prob']}")

if __name__ == "__main__":
    main()
