# main.py - FastAPI server com WebSockets e Diagnóstico de Áudio
import os
import shutil
import uuid
import json
import asyncio
import io
import time # Necessário para o novo diagnóstico de tamanho
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from subprocess import Popen, PIPE, TimeoutExpired
from concurrent.futures import ThreadPoolExecutor
from typing import List

# --- CONFIGURAÇÃO GLOBAL E PATHS ---
# Caminhos devem corresponder ao Dockerfile
WHISPER_BIN = "/app/main-whisper"
MODEL_PATH = "/app/models/ggml-tiny.bin"
UPLOAD_DIR = "/tmp/uploads"

# Configuração do executor para rodar tarefas bloqueantes (CPU-bound)
executor = ThreadPoolExecutor(max_workers=1)

# Cria a pasta de upload temporária
os.makedirs(UPLOAD_DIR, exist_ok=True)

app = FastAPI()

# --- CONFIGURAÇÃO CORS ---
origins = [
    "https://nexuspsi.com.br",
    "http://localhost",
    "http://127.0.0.1",
    "null"
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- FUNÇÕES DE AJUDA ---

def cleanup_paths(paths: List[str]):
    """Remove arquivos do disco, ignorando erros."""
    for path in paths:
        try:
            os.remove(path)
        except OSError:
            pass

# main.py - DENTRO da função convert_and_transcribe_sync

def convert_and_transcribe_sync(raw_audio_data: bytes, segment_id: str) -> str:
    """
    MODO TESTE: Tenta transcrever um arquivo WAV estático (test.wav)
    para verificar se o binário e o modelo estão funcionando.
    """
    test_wav_path = "/app/test.wav" 
    
    if not os.path.exists(test_wav_path) or os.path.getsize(test_wav_path) < 100:
        return "ERRO DE TESTE: test.wav não encontrado ou vazio no contêiner."

    try:
        # 3. EXECUTAR WHISPER.CPP com o arquivo de teste
        proc = Popen([
            WHISPER_BIN, 
            "-m", MODEL_PATH, 
            "-f", test_wav_path, # Usa o arquivo de teste!
            "-l", "auto",
            "-t", "4", "-p", "0" 
        ], stdout=PIPE, stderr=PIPE)
        
        out, err = proc.communicate(timeout=15) # Timeout reduzido para teste
        
        if proc.returncode != 0:
             whisper_stderr = err.decode('utf-8', errors='ignore')
             # Se o Whisper falhar, o problema é permissão ou modelo
             raise Exception(f"ERRO CRÍTICO (TESTE). STDERR: {whisper_stderr}")

        # 4. EXTRAIR O TEXTO
        output = out.decode('utf-8', errors='ignore')
        transcribed_text = output.strip().split('\n')[-1].split(':')[-1].strip()
        
        return f"[TESTE SUCESSO] Texto: {transcribed_text}"

    finally:
        # Limpeza não é necessária, apenas diagnóstico
        pass

# --- ENDPOINT WEBSOCKET DE STREAMING (CORRIGIDO PARA ASGI) ---

@app.get("/")
async def root():
    return {"status":"ok"}

@app.websocket("/ws/transcribe_stream")
async def websocket_transcription_endpoint(websocket: WebSocket):
    await websocket.accept()
    print("WebSocket connection accepted.")
    
    # Buffer para acumular áudio entre chunks
    audio_buffer = io.BytesIO()
    segment_counter = 0

    try:
        while True:
            # 1. RECEBE CHUNK BINÁRIO DO CLIENTE
            data = await websocket.receive_bytes()
            
            if data:
                audio_buffer.write(data)
                
                segment_counter += 1
                segment_id = f"seg_{segment_counter}_{time.time()}"
                
                buffer_content = audio_buffer.getvalue()
                audio_buffer = io.BytesIO() # Reseta o buffer

                # 2. RODA O PROCESSAMENTO NO EXECUTOR
                loop = asyncio.get_event_loop()
                transcribed_text = await loop.run_in_executor(
                    executor,
                    convert_and_transcribe_sync,
                    buffer_content,
                    segment_id
                )

                # 3. ENVIA O RESULTADO TRANSCRITO
                await websocket.send_json({"text": transcribed_text, "status": "chunk_complete"})
                print(f"Segmento {segment_id} processado. Texto: {transcribed_text[:40]}...")

    except WebSocketDisconnect:
        # 4. TRATAMENTO DE DESCONEXÃO NORMAL
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
        # 5. TRATAMENTO DE ERRO INESPERADO (Evita o RuntimeError de fechamento)
        print(f"ERRO CRÍTICO no WebSocket: {e}")
        try:
            await websocket.send_json({"error": f"Erro interno do servidor: {str(e)}", "status": "server_error"})
            await websocket.close(code=status.WS_1011_INTERNAL_ERROR) 
        except Exception:
            pass 
    
    finally:
        # Limpeza final de recursos
        audio_buffer.close()
        print("WebSocket handler finished.")

