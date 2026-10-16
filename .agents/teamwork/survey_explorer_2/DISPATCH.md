## 2026-10-16T18:13:15Z
You are survey_explorer_2, an exploration agent.
Your working directory is: c:\Users\david\Documents\micgame-3\.agents\teamwork\survey_explorer_2\
The authoritative user specification is at: c:\Users\david\Documents\micgame-3\.agents\teamwork\ORIGINAL_REQUEST.md
Project root is: c:\Users\david\Documents\micgame-3

Your task:
1. Read c:\Users\david\Documents\micgame-3\.agents\teamwork\ORIGINAL_REQUEST.md thoroughly.
2. Investigate the project root and environment for audio capture, machine learning, and inference components:
   - What tools/runtimes are available (Python, ONNX Runtime, pip packages, numpy, scipy, etc.)?
   - Spotify Basic Pitch model (`basic-pitch`): how it runs, ONNX weights availability, input/output tensors, sample rates (22050Hz vs 44100/48000Hz), windowing/hop size, polyphonic note detection, onset detection.
   - Low latency audio input capture in Godot (AudioServer, AudioEffectCapture, AudioStreamMicrophone) and bridge to the inference engine.
   - Modular inference architecture: how to structure a pluggable model runner interface so future instrument models, source separation, and fine-tuning pipelines can be cleanly plugged in.
   - Real-time/streaming vs chunk-based scoring logic: pitch matching (semitone tolerance), timing window (+/- 100ms), polyphonic chord matching, duration evaluation.
3. Detail all existing files, missing components, model files needed, tensor requirements, latency considerations, and technical risks.
4. Write your comprehensive survey report to `c:\Users\david\Documents\micgame-3\.agents\teamwork\survey_explorer_2\report.md` and complete your `handoff.md` and update `progress.md`.
5. Send a message back to the orchestrator summarizing your findings and referencing your report path.
