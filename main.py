# main.py - FastAPI server com WebSockets para Streaming em Tempo Real
import os, shutil, uuid
import wave # Necessário para lidar com chunks de áudio
from fastapi import FastAPI, File, UploadFile, HTTPException, WebSocket, Depends, status
from fastapi.responses import JSONResponse
from subprocess import Popen, PIPE, TimeoutExpired
from io import BytesIO # Para processar dados binários na memória

# ✅ 1. Importar o Middleware de CORS
from fastapi.middleware.cors import CORSMiddleware
from fastapi.websockets import WebSocketDisconnect # Para lidar com a desconexão

app = FastAPI()

# ✅ 2. Definir as origens permitidas (seu site)
origins = [
    "https://nexuspsi.com.br",
    "http://localhost",
    "http://127.0.0.1",
    "null"
]

# ✅ 3. Adicionar o Middleware de CORS ao app
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- O RESTO DO SEU CÓDIGO ---

# ✅ 4. CAMINHOS ATUALIZADOS
WHISPER_BIN = "/app/main-whisper"                # Caminho do executável pré-compilado
MODEL_PATH = "/app/models/ggml-tiny.bin"         # Caminho do modelo 'tiny'

UPLOAD_DIR = "/tmp/uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)

# -------------------------------------------------------------
# FUNÇÕES AUXILIARES
# -------------------------------------------------------------

def cleanup_paths(paths):
    for p in paths:
        try:
            if os.path.exists(p):
                os.remove(p)
        except:
            pass

def process_chunk_and_transcribe(wav_data: bytes) -> str:
    """
    Salva o chunk WAV na memória e o transcreve usando whisper.cpp.
    """
    file_id = str(uuid.uuid4())
    wav_path = os.path.join(UPLOAD_DIR, f"{file_id}.wav")

    # Salva o buffer na memória como um arquivo WAV temporário
    with open(wav_path, "wb") as f:
        f.write(wav_data)

    # Executa whisper.cpp (usamos um timeout mais curto para chunks)
    try:
        proc = Popen([WHISPER_BIN, "-m", MODEL_PATH, "-f", wav_path, "-l", "auto", "--no-timestamps"], stdout=PIPE, stderr=PIPE)
        # Timeout reduzido, pois esperamos que o chunk seja pequeno (ex: 30 segundos de áudio)
        out, err = proc.communicate(timeout=45) 
    except TimeoutExpired:
        raise Exception("Whisper chunk timeout") # Lançar exceção para ser capturada pelo websocket

    cleanup_paths([wav_path])
    text_out = out.decode(errors="ignore").strip()
    
    # Se a saída estiver vazia, verifica o erro (pode ser o próprio texto)
    if not text_out:
        text_out = err.decode(errors="ignore").strip()
    
    # O Whisper retorna várias linhas, pegamos apenas a transcrição principal
    return text_out.split('\n')[-1].strip()

# -------------------------------------------------------------
# ENDPOINT DE ARQUIVO COMPLETO (Se você ainda precisar dele)
# -------------------------------------------------------------

@app.get("/")
async def root():
    return {"status":"ok"}

@app.post("/transcribe")
async def transcribe(audio: UploadFile = File(...)):
    # salva arquivo recebido
    file_id = str(uuid.uuid4())
    raw_path = os.path.join(UPLOAD_DIR, f"{file_id}_{audio.filename}")
    with open(raw_path, "wb") as f:
        shutil.copyfileobj(audio.file, f)

    wav_path = raw_path + ".wav"
    # converte para WAV 16k mono
    try:
        p = Popen(["ffmpeg", "-y", "-i", raw_path, "-ac", "1", "-ar", "16000", wav_path], stdout=PIPE, stderr=PIPE)
        out, err = p.communicate(timeout=600) # AUMENTADO PARA EVITAR FALHA EM ÁUDIOS LONGOS
    except TimeoutExpired:
        cleanup_paths([raw_path])
        raise HTTPException(status_code=500, detail="ffmpeg timeout")

    if not os.path.exists(wav_path):
        cleanup_paths([raw_path])
        raise HTTPException(status_code=500, detail="Conversion failed")

    # executa whisper.cpp
    try:
        proc = Popen([WHISPER_BIN, "-m", MODEL_PATH, "-f", wav_path, "-l", "auto"], stdout=PIPE, stderr=PIPE)
        out, err = proc.communicate(timeout=1800) # AUMENTADO MUITO PARA ÁUDIOS LONGOS
    except TimeoutExpired:
        cleanup_paths([raw_path, wav_path])
        raise HTTPException(status_code=500, detail="whisper timeout")

    cleanup_paths([raw_path, wav_path])
    text_out = out.decode(errors="ignore").strip()
    if not text_out:
        text_out = err.decode(errors="ignore").strip()
    
    return JSONResponse({"text": text_out})

# -------------------------------------------------------------
# ✅ NOVO ENDPOINT DE WEBSOCKETS PARA STREAMING EM TEMPO REAL
# -------------------------------------------------------------

# Tamanho do buffer em segundos * taxa de amostragem * canais * tamanho do sample (16-bit)
# Se o áudio for 16000Hz, 1 canal, 16-bit (2 bytes): 16000 * 1 * 2 = 32000 bytes por segundo
CHUNK_DURATION_SECONDS = 30 # Processar a cada 30 segundos de áudio
SAMPLE_RATE = 16000
CHUNK_BUFFER_SIZE = CHUNK_DURATION_SECONDS * SAMPLE_RATE * 2 # 960,000 bytes para 30 segundos de 16-bit PCM

@app.websocket("/ws/transcribe_stream")
async def websocket_transcription_endpoint(websocket: WebSocket):
    await websocket.accept()
    audio_buffer = bytearray()
    
    try:
        while True:
            # Recebe dados binários (esperamos pacotes PCM de 16kHz)
            data = await websocket.receive_bytes()
            audio_buffer.extend(data)
            
            # Se o buffer atingiu o tamanho para um chunk processável
            if len(audio_buffer) >= CHUNK_BUFFER_SIZE:
                
                # Pega a primeira parte do buffer para processamento
                chunk_to_process = audio_buffer[:CHUNK_BUFFER_SIZE]
                
                # Remove o chunk processado do buffer original
                audio_buffer = audio_buffer[CHUNK_BUFFER_SIZE:]

                # Chama a função de processamento (que salva e chama whisper.cpp)
                try:
                    transcribed_text = process_chunk_and_transcribe(chunk_to_process)
                    
                    # Envia o resultado de volta para o cliente
                    if transcribed_text:
                        await websocket.send_json({"text": transcribed_text, "status": "chunk_processed"})
                        
                except Exception as e:
                    print(f"Erro ao processar chunk: {e}")
                    await websocket.send_json({"error": str(e), "status": "processing_failed"})

    except WebSocketDisconnect:
        print("Cliente desconectado.")
    except Exception as e:
        print(f"Erro inesperado no WebSocket: {e}")
        
    finally:
        # Se houver áudio restante no buffer, processa o final
        if len(audio_buffer) > 0:
            try:
                transcribed_text = process_chunk_and_transcribe(audio_buffer)
                if transcribed_text:
                    await websocket.send_json({"text": transcribed_text, "status": "final_chunk"})
            except Exception as e:
                print(f"Erro ao processar chunk final: {e}")
        await websocket.close()
