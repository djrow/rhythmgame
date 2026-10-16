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

def resample_linear(audio, orig_sr, target_sr=22050):
    if orig_sr == target_sr:
        return audio
    num_target_samples = int(len(audio) * target_sr / orig_sr)
    t_orig = np.arange(len(audio)) / orig_sr
    t_target = np.arange(num_target_samples) / target_sr
    return np.interp(t_target, t_orig, audio).astype(np.float32)

def argrelmax_axis0(mat):
    """Pure numpy replacement for scipy.signal.argrelmax(mat, axis=0)."""
    peaks = np.zeros_like(mat, dtype=bool)
    if mat.shape[0] < 3:
        return peaks
    peaks[1:-1] = (mat[1:-1] > mat[:-2]) & (mat[1:-1] >= mat[2:])
    return peaks

def infer_onsets_numpy(onsets, frames, n_diff=2):
    """Infers additional onsets from large changes in frame activations."""
    diffs = []
    for n in range(1, n_diff + 1):
        appended = np.concatenate([np.zeros((n, frames.shape[1]), dtype=np.float32), frames])
        diffs.append(appended[n:, :] - appended[:-n, :])
    frame_diff = np.min(diffs, axis=0)
    frame_diff[frame_diff < 0] = 0
    frame_diff[:n_diff, :] = 0
    max_diff = np.max(frame_diff)
    if max_diff > 0:
        frame_diff = np.max(onsets) * frame_diff / max_diff
    return np.maximum(onsets, frame_diff)

def transcribe_audio_pure_numpy(audio, sample_rate, session, 
                                onset_thresh=0.50, frame_thresh=0.40, 
                                min_note_len_frames=4, energy_tol=11):
    """
    Full audio file transcription in pure NumPy + ONNX Runtime.
    """
    audio = resample_linear(audio, sample_rate, 22050)
    audio_len = len(audio)
    
    AUDIO_N_SAMPLES = 43844
    FFT_HOP = 256
    fps = 22050.0 / 256.0
    
    # Use 30 overlapping frames (15 on each side trimmed)
    n_overlapping_frames = 30
    overlap_len = n_overlapping_frames * FFT_HOP # 7680
    hop_size = AUDIO_N_SAMPLES - overlap_len     # 36164
    n_olap = int(0.5 * n_overlapping_frames)     # 15
    
    # Pre-roll padding: 1 window half (or at least overlap_len)
    # To place t=0 at exactly n_olap frames in the first unwrapped window:
    # First window will have n_olap frames trimmed from start.
    # So if audio starts at sample (n_olap * FFT_HOP), the first sample of audio aligns with frame 0 of unwrapped output!
    pad_start_samples = n_olap * FFT_HOP # 15 * 256 = 3840
    # Add an extra hop or 0.5s padding so the first onset is not right at boundary 0
    extra_pad_frames = 30
    extra_pad_samples = extra_pad_frames * FFT_HOP
    total_pad_samples = pad_start_samples + extra_pad_samples
    
    padded_audio = np.concatenate([
        np.zeros(total_pad_samples, dtype=np.float32),
        audio,
        np.zeros(AUDIO_N_SAMPLES, dtype=np.float32)
    ])
    
    # Collect predictions
    note_windows = []
    onset_windows = []
    input_name = session.get_inputs()[0].name
    
    for i in range(0, len(padded_audio) - overlap_len, hop_size):
        chunk = padded_audio[i : i + AUDIO_N_SAMPLES]
        if len(chunk) < AUDIO_N_SAMPLES:
            chunk = np.pad(chunk, (0, AUDIO_N_SAMPLES - len(chunk)))
        
        inp = chunk.reshape(1, AUDIO_N_SAMPLES, 1)
        outs = session.run(None, {input_name: inp})
        out_dict = {o.name: outs[idx] for idx, o in enumerate(session.get_outputs())}
        
        cur_onset = out_dict['StatefulPartitionedCall:2'] # (1, 172, 88)
        cur_note = out_dict['StatefulPartitionedCall:1']  # (1, 172, 88)
        
        onset_windows.append(cur_onset)
        note_windows.append(cur_note)
        
    onsets_concat = np.concatenate(onset_windows, axis=0) # (B, 172, 88)
    notes_concat = np.concatenate(note_windows, axis=0)   # (B, 172, 88)
    
    # Unwrap output: remove n_olap from each side
    onsets_trimmed = onsets_concat[:, n_olap:-n_olap, :] # (B, 142, 88)
    notes_trimmed = notes_concat[:, n_olap:-n_olap, :]   # (B, 142, 88)
    
    B, T_trim, F_bins = onsets_trimmed.shape
    unwrapped_onsets = onsets_trimmed.reshape(B * T_trim, F_bins)
    unwrapped_notes = notes_trimmed.reshape(B * T_trim, F_bins)
    
    # Shift back by extra_pad_frames
    unwrapped_onsets = unwrapped_onsets[extra_pad_frames:]
    unwrapped_notes = unwrapped_notes[extra_pad_frames:]
    
    # Trim to original length in frames
    n_output_frames = int(np.floor(audio_len * (fps / 22050.0)))
    unwrapped_onsets = unwrapped_onsets[:n_output_frames, :]
    unwrapped_notes = unwrapped_notes[:n_output_frames, :]
    
    # Post-processing note creation
    frames = unwrapped_notes
    onsets = infer_onsets_numpy(unwrapped_onsets, frames)
    
    peaks_mask = argrelmax_axis0(onsets)
    peak_thresh_mat = np.zeros_like(onsets)
    peak_thresh_mat[peaks_mask] = onsets[peaks_mask]
    
    onset_idx = np.where(peak_thresh_mat >= onset_thresh)
    onset_time_idx = onset_idx[0][::-1]
    onset_freq_idx = onset_idx[1][::-1]
    
    remaining_energy = frames.copy()
    note_events = []
    
    n_total_frames = frames.shape[0]
    for note_start_idx, freq_idx in zip(onset_time_idx, onset_freq_idx):
        if note_start_idx >= n_total_frames - 1:
            continue
            
        i = note_start_idx + 1
        k = 0
        while i < n_total_frames - 1 and k < energy_tol:
            if remaining_energy[i, freq_idx] < frame_thresh:
                k += 1
            else:
                k = 0
            i += 1
        i -= k
        
        if i - note_start_idx <= min_note_len_frames:
            continue
            
        remaining_energy[note_start_idx:i, freq_idx] = 0
        if freq_idx < 87:
            remaining_energy[note_start_idx:i, freq_idx + 1] = 0
        if freq_idx > 0:
            remaining_energy[note_start_idx:i, freq_idx - 1] = 0
            
        amplitude = float(np.mean(frames[note_start_idx:i, freq_idx]))
        start_sec = note_start_idx / fps
        end_sec = i / fps
        dur_sec = end_sec - start_sec
        pitch_midi = freq_idx + 21
        
        note_events.append({
            "pitch": pitch_midi,
            "onset_sec": round(start_sec, 3),
            "duration_sec": round(dur_sec, 3),
            "confidence": round(amplitude, 3),
            "onset_prob": round(float(onsets[note_start_idx, freq_idx]), 3)
        })
        
    note_events.sort(key=lambda x: x["onset_sec"])
    return note_events

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
            
        detected = transcribe_audio_pure_numpy(audio, sr, session, onset_thresh=0.50, frame_thresh=0.40)
        metrics = evaluate_metrics(detected, chart["notes"], onset_tolerance=0.15)
        
        print(f"\n=======================================================")
        print(f"Piece: {chart['title']} ({wav_name})")
        print(f"Ground Truth Notes: {len(chart['notes'])}, Detected: {len(detected)}")
        print(f"TP: {metrics['tp']}, FP: {metrics['fp']}, FN: {metrics['fn']}")
        print(f"Precision: {metrics['precision']*100:.1f}%, Recall: {metrics['recall']*100:.1f}%, F1-Score: {metrics['f1']*100:.1f}%")

if __name__ == "__main__":
    main()
