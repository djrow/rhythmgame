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

def run_offline_transcription(audio, sample_rate, session, note_thresh=0.40, onset_thresh=0.45):
    """
    Offline transcription using overlapping windows of 43,844 samples.
    Returns list of transcribed notes: [{"pitch": midi, "onset_sec": t, "duration_sec": d}]
    """
    window_samples = 43844
    hop_samples = 22050 # 1 second hop for overlap, or 172*256 = 44032
    # In Basic Pitch: FFT hop is 256 samples, frame rate is 22050 / 256 = 86.1328 fps.
    # Total audio duration:
    total_samples = len(audio)
    
    # Let's accumulate frame activations across the entire audio
    # Total frames:
    n_total_frames = int(np.ceil(total_samples / 256)) + 172
    full_notes = np.zeros((n_total_frames, 88), dtype=np.float32)
    full_onsets = np.zeros((n_total_frames, 88), dtype=np.float32)
    counts = np.zeros((n_total_frames, 1), dtype=np.float32)
    
    # Overlap step: e.g. half window = 22000 samples (~86 frames)
    step = 22016 # 86 * 256
    
    for start_sample in range(0, total_samples, step):
        chunk = np.zeros(window_samples, dtype=np.float32)
        end_sample = min(start_sample + window_samples, total_samples)
        valid_len = end_sample - start_sample
        chunk[:valid_len] = audio[start_sample:end_sample]
        
        inp = chunk.reshape(1, window_samples, 1)
        outs = session.run(None, {'serving_default_input_2:0': inp})
        
        # Output mapping
        # StatefulPartitionedCall:2 -> onsets
        # StatefulPartitionedCall:1 -> notes
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
    
    # Extract note events
    # For each pitch bin (0..87, MIDI 21..108):
    detected_notes = []
    fps = 22050.0 / 256.0
    
    for b in range(88):
        pitch = b + 21
        prob = full_notes[:, b]
        ons = full_onsets[:, b]
        
        # Find active intervals
        is_active = (prob >= note_thresh)
        in_note = False
        start_f = 0
        
        for f in range(len(is_active)):
            if is_active[f] and not in_note:
                # Potential note onset
                in_note = True
                start_f = f
            elif not is_active[f] and in_note:
                in_note = False
                end_f = f
                dur = (end_f - start_f) / fps
                if dur >= 0.05: # Min 50ms duration
                    onset_t = start_f / fps
                    # Check if there is an onset peak near start_f
                    onset_window = ons[max(0, start_f - 3): min(len(ons), start_f + 4)]
                    max_onset = onset_window.max() if len(onset_window) > 0 else 0
                    detected_notes.append({
                        "pitch": pitch,
                        "onset_sec": round(onset_t, 3),
                        "duration_sec": round(dur, 3),
                        "confidence": float(prob[start_f:end_f].mean()),
                        "onset_prob": float(max_onset)
                    })
        if in_note:
            end_f = len(is_active)
            dur = (end_f - start_f) / fps
            if dur >= 0.05:
                detected_notes.append({
                    "pitch": pitch,
                    "onset_sec": round(start_f / fps, 3),
                    "duration_sec": round(dur, 3),
                    "confidence": float(prob[start_f:end_f].mean()),
                    "onset_prob": float(ons[start_f:min(len(ons), start_f+3)].max())
                })
                
    detected_notes.sort(key=lambda x: x["onset_sec"])
    return detected_notes

def evaluate_metrics(detected, ground_truth, onset_tolerance=0.15, pitch_tolerance=0):
    """
    Evaluates note-level Precision, Recall, and F1-score against ground truth notes.
    """
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
            
        detected = run_offline_transcription(audio, sr, session, note_thresh=0.38, onset_thresh=0.40)
        metrics = evaluate_metrics(detected, chart["notes"], onset_tolerance=0.15)
        
        print(f"\n--- {chart['title']} ({wav_name}) ---")
        print(f"Ground Truth Notes: {len(chart['notes'])}, Detected: {len(detected)}")
        print(f"TP: {metrics['tp']}, FP: {metrics['fp']}, FN: {metrics['fn']}")
        print(f"Precision: {metrics['precision']*100:.1f}%, Recall: {metrics['recall']*100:.1f}%, F1: {metrics['f1']*100:.1f}%")
        
        # Check first 5 detected vs expected
        print("Sample detected notes (first 5):")
        for n in detected[:5]:
            print(f"  Pitch: {n['pitch']}, Onset: {n['onset_sec']}s, Dur: {n['duration_sec']}s, Conf: {n['confidence']:.2f}")

if __name__ == "__main__":
    main()
