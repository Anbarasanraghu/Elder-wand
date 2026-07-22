# Retraining the "Elder Wand" wake word (Colab)

## Why we're doing this
The current model was trained with the notebook's **"quick test" defaults**
(n_samples=1000, target_recall=0.25). Proof: it scores **0.94 on Piper TTS**
but **0.0006 on your real voice** — it memorized the synthetic voice and
ignores real ones. The app/pipeline are correct (a Python replica of the phone
code scored 0.948 on TTS). Fix = retrain properly with augmentation + more data.

## The notebook
Open this (Google account required, free):
https://colab.research.google.com/github/alfiedennen/openwakeword-colab-2026/blob/main/train_wakeword.ipynb

Free T4 GPU works (~2-3 hrs). Colab Pro L4 is faster (~90 min) but not required.

## Steps
1. Open the link above.
2. Top menu: **Runtime → Change runtime type → GPU (T4)** → Save.
3. Find **Cell 10** (the configuration cell). Set exactly:
   ```python
   TARGET_PHRASE = ['elder wand']
   MODEL_NAME    = 'Elder_wand'
   ```
4. For better real-voice recall, also bump these (in the same/optional config):
   ```python
   n_samples           = 5000     # more positive examples (default is lower)
   augmentation_rounds = 2        # more noise/reverb variety per clip
   target_recall       = 0.6
   ```
5. **Runtime → Run all**. Keep the browser tab open/active so it doesn't
   disconnect. It generates thousands of augmented "Elder Wand" clips, trains,
   and reports accuracy.
6. When done it produces **Elder_wand.onnx** (sigmoid baked in, 0-1 output,
   0.5 threshold). Download it.
7. Send me `Elder_wand.onnx`. I will:
   - convert it to `Elder_wand.tflite`,
   - drop both into `akeriyan_app/assets/wakeword/`,
   - rebuild the phone app,
   - and re-run the same real-voice test to confirm it now scores high on YOUR voice.

## Note
This notebook uses synthetic TTS + heavy augmentation, which is how the good
pretrained models (alexa, hey_jarvis) generalize to real voices — so you do NOT
need to upload your own recordings for it to work. (I already saved 22 clips of
your voice under wakeword_training/real_samples/ in case a later step wants them.)
