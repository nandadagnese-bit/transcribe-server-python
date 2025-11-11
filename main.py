# main.py - FastAPI server que recebe audio e chama whisper.cpp
import os, shutil, uuid
from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.responses import JSONResponse
from subprocess import Popen, PIPE, TimeoutExpired

# ✅ 1. Importar o Middleware de CORS
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

# ✅ 2. Definir as origens permitidas (seu site)
origins = [
    "https://nexuspsi.com.br",  # Seu site de produção
    "http://localhost",         # Para testes locais
    "http://127.0.0.1",       # Para testes locais
    "null"                      # Para testes abrindo o HTML localmente (file://)
]

# ✅ 3. Adicionar o Middleware de CORS ao app
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,       # Lista de origens permitidas
    allow_credentials=True,    # Permitir credenciais (cookies, etc)
    allow_methods=["*"],       # Permitir todos os métodos (GET, POST, etc)
    allow_headers=["*"],       # Permitir todos os cabeçalhos
)

# --- O RESTO DO SEU CÓDIGO PERMANECE IGUAL ---

WHISPER_BIN = "/whisper.cpp/main"          # whisper.cpp compilado
MODEL_PATH = "/app/models/ggml-small.bin"      # modelo baixado no Dockerfile
UPLOAD_DIR = "/tmp/uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)

@app.get("/")
async def root():
    return {"status":"ok"}

@app.post("/transcribe")
async def transcribe(audio: UploadFile = File(...)):
    # ... (seu código de transcrição continua aqui) ...
    file_id = str(uuid.uuid4())
    raw_path = os.path.join(UPLOAD_DIR, f"{file_id}_{audio.filename}")
    with open(raw_path, "wb") as f:
        shutil.copyfileobj(audio.file, f)

    wav_path = raw_path + ".wav"
    try:
        p = Popen(["ffmpeg", "-y", "-i", raw_path, "-ac", "1", "-ar", "16000", wav_path], stdout=PIPE, stderr=PIPE)
        out, err = p.communicate(timeout=30)
    except TimeoutExpired:
        cleanup_paths([raw_path])
        raise HTTPException(status_code=500, detail="ffmpeg timeout")

    if not os.path.exists(wav_path):
        cleanup_paths([raw_path])
        raise HTTPException(status_code=500, detail="Conversion failed")

    try:
        proc = Popen([WHISPER_BIN, "-m", MODEL_PATH, "-f", wav_path], stdout=PIPE, stderr=PIPE)
        out, err = proc.communicate(timeout=120)
    except TimeoutExpired:
        cleanup_paths([raw_path, wav_path])
        raise HTTPException(status_code=500, detail="whisper timeout")

    cleanup_paths([raw_path, wav_path])
    text_out = out.decode(errors="ignore").strip()
    if not text_out:
        text_out = err.decode(errors="ignore").strip()
    return JSONResponse({"text": text_out})

def cleanup_paths(paths):
    for p in paths:
        try:
            if os.path.exists(p):
                os.remove(p)
        except:
            pass
