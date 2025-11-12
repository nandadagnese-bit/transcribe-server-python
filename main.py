# main.py - Versão de Diagnóstico Final (FFmpeg/WAV Check)
import os
import shutil
import uuid
import json
import asyncio
import io
import time
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from subprocess import Popen, PIPE, TimeoutExpired
from concurrent.futures import ThreadPoolExecutor
from typing import List
from starlette import status # Necessário para o código de status do WebSocket

# --- CONFIGURAÇÃO GLOBAL E PATHS ---
WHISPER_BIN = "/app/main-whisper"
MODEL_PATH = "/app/models/ggml-tiny.bin"
UPLOAD_DIR = "/tmp/uploads"

executor = ThreadPoolExecutor(max_workers=1)
os.makedirs(UPLOAD_DIR, exist_ok=True)
app = FastAPI()

# --- CONFIGURAÇÃO CORS ---
origins = ["https://nexuspsi.com.br", "http://localhost", "http://127.0.0.1", "null"]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- FUNÇÕES DE AJUDA ---

def cleanup_paths(paths: List[str]):
    for path in paths:
        try:
            os.remove(path)
        except OSError:
            pass

def convert_and_transcribe_sync(raw_audio_data: bytes, segment_id: str) -> str:
    """
    Função SÍNCRONA que converte o áudio RAW e chama o whisper.cpp.
    Inclui diagnóstico para falha de FFmpeg/WAV vazio.
    """
    raw_path = os.path.join(UPLOAD_DIR, f"{segment_id}.webm")
    wav_path = os.path.join(UPLOAD_DIR, f"{segment_id}.wav")

    try:
        # 1. SALVAR DADOS RAW (WebM/Opus)
        with open(raw_path, "wb") as f:
            f.write(raw_audio_data)

        # 2. CONVERTER PARA WAV 16kHz MONO (para o whisper.cpp)
        p = Popen([
            "ffmpeg", "-y", "-i", raw_path,
            "-ac", "1", "-ar", "16000",
            wav_path
        ], stdout=PIPE, stderr=PIPE)
        out, err = p.communicate(timeout=10)

        # ⭐️ DIAGNÓSTICO CRÍTICO: Verifica se o arquivo WAV foi criado corretamente ⭐️
        wav_size = 0
        if os.path.exists(wav_path):
             wav_size = os.path.getsize(wav_path)
             
        # Se o tamanho for inferior a 1000 bytes (WAV inválido ou vazio)
        if wav_size < 1000: 
            ffmpeg_error = err.decode('utf-8', errors='ignore')
            raise Exception(f"FFmpeg/WAV inválido. Tamanho WAV: {wav_size} bytes. Saída do FFmpeg: {ffmpeg_error}")

        # 3. EXECUTAR WHISPER.CPP
        proc = Popen([
            WHISPER_BIN, 
            "-m", MODEL_PATH, 
            "-f", wav_path, 
            "-l", "auto",
            "-t", "4",
            "-p", "0" 
        ], stdout=PIPE, stderr=PIPE)
        
        out, err = proc.communicate(timeout=300) 
        
        if proc.returncode != 0:
             whisper_stderr = err.decode('utf-8', errors='ignore')
             raise Exception(f"Whisper falhou (Código {proc.returncode}). STDERR: {whisper_stderr}")

        # 4. EXTRAIR O TEXTO
        output = out.decode('utf-8', errors="ignore")
        # Assume que o texto transcrito é o último pedaço de informação
        transcribed_text = output.strip().split('\n')[-1].split(':')[-1].strip()
        
        return transcribed_text

    finally:
        # 5. LIMPEZA
        cleanup_paths([raw_path, wav_path])

# --- ENDPOINT WEBSOCKET DE STREAMING (CORRIGIDO PARA ASGI) ---

@app.get("/")
async def root():
    return {"status":"ok"}

@app.websocket("/ws/transcribe_stream")
async def websocket_transcription_endpoint(websocket: WebSocket):
    await websocket.accept()
    print("WebSocket connection accepted.")
    
    audio_buffer = io.BytesIO()
    segment_counter = 0

    try:
        while True:
            data = await websocket.receive_bytes()
            
            if data:
                audio_buffer.write(data)
                
                segment_counter += 1
                segment_id = f"seg_{segment_counter}_{time.time()}"
                
                buffer_content = audio_buffer.getvalue()
                audio_buffer = io.BytesIO() # Reseta o buffer

                loop = asyncio.get_event_loop()
                transcribed_text = await loop.run_in_executor(
                    executor,
                    convert_and_transcribe_sync,
                    buffer_content,
                    segment_id
                )

                await websocket.send_json({"text": transcribed_text, "status": "chunk_complete"})
                print(f"Segmento {segment_id} processado. Texto: {transcribed_text[:40]}...")

    except WebSocketDisconnect:
        # TRATAMENTO DE DESCONEXÃO NORMAL
        print("Cliente desconectado (WebSocketDisconnect). Processando buffer final...")
        final_buffer_content = audio_buffer.getvalue()
        
        if final_buffer_content:
            try:
                loop = asyncio.get_event_loop()
                transcribed_text = await loop.run_in_executor(
                    executor,
                    convert_and_transcribe_sync,
                    final_buffer_content,
                    "seg_final"
                )
                await websocket.send_json({"text": transcribed_text, "status": "final_chunk_complete"})
            except Exception as e:
                print(f"Erro ao processar o chunk final: {e}")
                
    except Exception as e:
        # TRATAMENTO DE ERRO INESPERADO (Captura o erro de Whisper/FFmpeg e lança para o cliente)
        print(f"ERRO CRÍTICO no WebSocket: {e}")
        try:
            await websocket.send_json({"error": f"Erro interno do servidor: {str(e)}", "status": "server_error"})
            await websocket.close(code=status.WS_1011_INTERNAL_ERROR) 
        except Exception:
            pass
    
    finally:
        audio_buffer.close()
        print("WebSocket handler finished.")

