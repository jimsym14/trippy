# Active workspace

The current workspace on Crucial X9 is:

- Project root: `/Volumes/CrucialX9/Code_Backup/Trippy/project`
- Research audio and transcripts: `/Volumes/CrucialX9/Code_Backup/Trippy/research-audio`

Open the `project` directory as the coding workspace. The audio batch is a sibling directory so large media files stay outside Git. Its download manifest stores audio filenames relative to itself.

The Python environment is `.venv`. Its console launchers have been rebased to this path; Python 3.13 and the pinned dependency set are working. Whisper.cpp was rebuilt at `.local/asr/build-v1.9.5-relocated` and its verified multilingual model remains at `.local/asr/ggml-small.bin`. Use `--cpu-only` for transcription until the Metal backend initialization failure on downloaded audio is resolved.

The workspace verification run completed 112 Python tests. The real Whisper CPU smoke checks passed for both the upstream English sample and one downloaded Greek Barcelona clip. The 20-video transcription run finished with 19 structurally emitted evidence files and one failed transcript; quality flags are in `../research-audio/barcelona-transcripts-20261030-cpu/review-audit.json`.
