# Mahjong YOLO model source

- Project: `nikmomo/Mahjong-YOLO`
- Source: https://github.com/nikmomo/Mahjong-YOLO
- Source commit: `28ffceed232ad95fd019c47a6c51ae7c78791a0e`
- File: `models/nano/mahjong-yolon-best.onnx`
- SHA-256: `3c7732c022d41c1a3f48cea931ce626416d92486ab5b86692312941d0cc22226`
- Model size: 10,611,888 bytes
- Repository license: MIT
- Model family: YOLO11 nano
- Input: RGB float tensor `[1, 3, 640, 640]`
- Output: non-NMS detection tensor `[1, 42, 8400]`

The repository describes the model as trained for 38 tile-related classes,
including red fives and an unknown class. Maohjong maps red fives to the
corresponding ordinary five and keeps `UNKNOWN` as an unresolved candidate.

The source repository links its training photographs separately. Before a
public app release, re-check the training-data terms and retain any attribution
required by the dataset. The app does not upload user photographs or use a
hosted inference API.
