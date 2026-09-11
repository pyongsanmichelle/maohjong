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
- Output: non-NMS detection tensor `[1, 41, 8400]`

The bundled ONNX metadata declares 37 tile-related classes: the 34 standard
tiles and three red fives (`0m`, `0p`, and `0s`). Although the repository
README also describes an `UNKNOWN` class, it is not present in this exact model
file. Maohjong maps red fives to the corresponding ordinary five.

The source repository links its training photographs separately. Before a
public app release, re-check the training-data terms and retain any attribution
required by the dataset. The app does not upload user photographs or use a
hosted inference API.
