import sys
sys.path.insert(0, '.agents/teamwork/m3_explorer_2')
import test_pure_numpy_basic_pitch as tp
import onnxruntime as ort
import json

session = ort.InferenceSession('assets/models/nmp.onnx')
for wav, jsn in [("ode_to_joy.wav", "ode_to_joy.json"), ("bach_minuet.wav", "bach_minuet.json"), ("cadence_triads.wav", "cadence_triads.json")]:
    audio, sr = tp.read_wav_mono('assets/audio/' + wav)
    chart = json.load(open('assets/charts/' + jsn))
    print(f"\nGrid search for {chart['title']}:")
    best_f1 = 0
    best_p = None
    for ot in [0.40, 0.45, 0.50, 0.55, 0.60]:
        for ft in [0.30, 0.35, 0.40, 0.45]:
            for min_l in [3, 4, 5, 6]:
                det = tp.transcribe_audio_pure_numpy(audio, sr, session, onset_thresh=ot, frame_thresh=ft, min_note_len_frames=min_l)
                m = tp.evaluate_metrics(det, chart['notes'], onset_tolerance=0.15)
                if m['f1'] > best_f1:
                    best_f1 = m['f1']
                    best_p = (ot, ft, min_l, m['precision'], m['recall'], m['tp'], m['fp'], m['fn'])
    print(f"  Best F1: {best_f1*100:.1f}%, Params: onset_thresh={best_p[0]}, frame_thresh={best_p[1]}, min_len={best_p[2]}")
    print(f"  Precision: {best_p[3]*100:.1f}%, Recall: {best_p[4]*100:.1f}%, TP={best_p[5]}, FP={best_p[6]}, FN={best_p[7]}")
