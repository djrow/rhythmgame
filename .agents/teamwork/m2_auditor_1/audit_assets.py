import os
import json
import wave
import numpy as np
from PIL import Image
import music21 as m21

PROJECT_ROOT = r"c:\Users\david\Documents\micgame-3"
pieces = ['piece_1_monophonic', 'piece_2_harmony', 'piece_3_polyphonic']
base = os.path.join(PROJECT_ROOT, 'assets', 'test_pieces')

print('=== 1. VERIFYING 12 TEST ASSET FILES IN assets/test_pieces/ ===')

for p in pieces:
    p_dir = os.path.join(base, p)
    print(f'\n--- Inspecting {p} ---')
    
    # WAV Check
    wav_path = os.path.join(p_dir, 'audio.wav')
    assert os.path.exists(wav_path), f'{wav_path} missing'
    with wave.open(wav_path, 'rb') as wf:
        n_ch = wf.getnchannels()
        sampwidth = wf.getsampwidth()
        framerate = wf.getframerate()
        n_frames = wf.getnframes()
        raw = wf.readframes(n_frames)
        data = np.frombuffer(raw, dtype=np.int16)
        dur = n_frames / framerate
        rms = np.sqrt(np.mean(data.astype(np.float64)**2))
        peak = np.max(np.abs(data))
        print(f'WAV: rate={framerate}, ch={n_ch}, width={sampwidth}, frames={n_frames}, dur={dur:.2f}s, peak={peak}, rms={rms:.2f}')
        assert framerate == 22050, f'Bad framerate: {framerate}'
        assert n_ch == 1, f'Bad channel count: {n_ch}'
        assert sampwidth == 2, f'Bad sample width: {sampwidth}'
        assert n_frames > 0 and peak > 1000, f'Silent audio in {wav_path}'

    # PNG Check
    png_path = os.path.join(p_dir, 'score.png')
    assert os.path.exists(png_path), f'{png_path} missing'
    with Image.open(png_path) as im:
        fmt = im.format
        mode = im.mode
        size = im.size
        arr = np.array(im)
        black_pixels = int(np.sum(arr < 50))
        white_pixels = int(np.sum(arr > 200))
        print(f'PNG: format={fmt}, mode={mode}, size={size}, black_pixels={black_pixels}, white_pixels={white_pixels}')
        assert fmt == 'PNG', f'Not PNG: {fmt}'
        assert size == (1600, 900), f'Bad size: {size}'
        assert black_pixels > 1000, f'Score image appears blank or empty: {black_pixels} black pixels'

    # JSON Check
    json_path = os.path.join(p_dir, 'ground_truth.json')
    assert os.path.exists(json_path), f'{json_path} missing'
    with open(json_path, 'r', encoding='utf-8') as jf:
        chart = json.load(jf)
    notes = chart.get('notes', [])
    measures = chart.get('measures', [])
    bpm = chart.get('bpm')
    print(f'JSON: title="{chart.get("title")}", bpm={bpm}, measures={len(measures)}, notes={len(notes)}')
    assert len(notes) > 0, f'No notes in {json_path}'
    for n in notes:
        assert 'pitch_midi' in n and 21 <= n['pitch_midi'] <= 108
        assert 'time_sec' in n and n['time_sec'] >= 0
        assert 'duration_sec' in n and n['duration_sec'] > 0
        assert 'staff' in n and n['staff'] in ('treble', 'bass')

    # MIDI Check
    mid_path = os.path.join(p_dir, 'ground_truth.mid')
    assert os.path.exists(mid_path), f'{mid_path} missing'
    mf = m21.midi.MidiFile()
    mf.open(mid_path, 'rb')
    mf.read()
    mf.close()
    stream = m21.midi.translate.midiFileToStream(mf)
    total_pitches = 0
    midi_pitch_set = set()
    for elem in stream.flatten().notes:
        if isinstance(elem, m21.chord.Chord):
            total_pitches += len(elem.pitches)
            for pitch in elem.pitches:
                midi_pitch_set.add(pitch.midi)
        elif isinstance(elem, m21.note.Note):
            total_pitches += 1
            midi_pitch_set.add(elem.pitch.midi)

    chart_pitch_set = {n['pitch_midi'] for n in notes}
    print(f'MID: size={os.path.getsize(mid_path)} bytes, tracks={len(mf.tracks)}, total_pitches={total_pitches}, unique_pitches={len(midi_pitch_set)}')
    assert total_pitches == len(notes), f'MIDI note count ({total_pitches}) != chart notes ({len(notes)})'
    assert midi_pitch_set == chart_pitch_set, f'MIDI pitch set mismatch: {midi_pitch_set} vs {chart_pitch_set}'

print('\n=== ALL 12 ASSET FILES PASSED DEEP VALIDATION! ===')
