# main.py - FastAPI server com WebSockets para Transcrição em Tempo Real
import os
import shutil
import uuid
import json
import asyncio
import io
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from subprocess import Popen, PIPE, TimeoutExpired
from concurrent.futures import ThreadPoolExecutor
from typing import List

# --- CONFIGURAÇÃO GLOBAL E PATHS ---
# ✅ PATHS ATUALIZADOS (conforme o Dockerfile e compilação)
WHISPER_BIN = "/app/main-whisper"
MODEL_PATH = "/app/models/ggml-tiny.bin"
UPLOAD_DIR = "/tmp/uploads"

# Configuração do executor para rodar tarefas bloqueantes (CPU-bound)
# Usamos ThreadPoolExecutor para rodar o subprocesso do whisper.cpp
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

def convert_and_transcribe_sync(raw_audio_data: bytes, segment_id: str) -> str:
    """
    Função SÍNCRONA que converte o áudio RAW e chama o whisper.cpp.
    Esta função deve ser executada no ThreadPoolExecutor.
    """
    raw_path = os.path.join(UPLOAD_DIR, f"{segment_id}.webm")
    wav_path = os.path.join(UPLOAD_DIR, f"{segment_id}.wav")

    try:
        # 1. SALVAR DADOS RAW (WebM/Opus)
        with open(raw_path, "wb") as f:
            f.write(raw_audio_data)

        # 2. CONVERTER PARA WAV 16kHz MONO (para o whisper.cpp)
        # O ffmpeg é crucial para lidar com o codec Opus
        p = Popen([
            "ffmpeg", "-y", "-i", raw_path,
            "-ac", "1", "-ar", "16000",
            wav_path
        ], stdout=PIPE, stderr=PIPE)
        out, err = p.communicate(timeout=10) # Timeout reduzido
        
        if not os.path.exists(wav_path):
            # Tenta mostrar o erro do FFmpeg
            raise Exception(f"FFmpeg falhou. STDERR: {err.decode('utf-8', errors='ignore')}")

        # 3. EXECUTAR WHISPER.CPP
        proc = Popen([
            WHISPER_BIN, 
            "-m", MODEL_PATH, 
            "-f", wav_path, 
            "-l", "auto",
            "-t", "4",  # Usa 4 threads para processamento mais rápido
            "-p", "0"   # Desabilita o print de progresso
        ], stdout=PIPE, stderr=PIPE)
        
        out, err = proc.communicate(timeout=45) # Timeout estendido para o Whisper
        
        if proc.returncode != 0:
             raise Exception(f"Whisper falhou (Código {proc.returncode}). STDERR: {err.decode('utf-8', errors='ignore')}")

        # 4. EXTRAIR O TEXTO
        output = out.decode('utf-8', errors='ignore')
        
        # Encontra o texto final na saída do whisper.cpp (última linha)
        transcribed_text = output.strip().split('\n')[-1].split(':')[-1].strip()
        
        return transcribed_text

    finally:
        # 5. LIMPEZA
        cleanup_paths([raw_path, wav_path])

# --- ENDPOINT OBSOLETO (MANTIDO COMENTADO) ---

# @app.post("/transcribe")
# async def transcribe_audio_post(audio: UploadFile = File(...)):
#     """Endpoint para receber um arquivo de áudio via POST (OBSELETO)."""
#     # Este endpoint é a causa do erro 500 por timeout. 
#     # A nova arquitetura usa WebSockets.
#     raise HTTPException(status_code=501, detail="Endpoint /transcribe obsoleto. Use /ws/transcribe_stream.")

# --- ENDPOINT WEBSOCKET DE STREAMING (CORRIGIDO) ---

@app.websocket("/ws/transcribe_stream")
async def websocket_transcription_endpoint(websocket: WebSocket):
    await websocket.accept()
    print("WebSocket connection accepted.")
    
    # Buffer para acumular áudio entre chunks (cerca de 4 segundos)
    audio_buffer = io.BytesIO()
    # Contador para identificar o segmento
    segment_counter = 0

    try:
        while True:
            # 1. RECEBE CHUNK BINÁRIO DO CLIENTE
            data = await websocket.receive_bytes()
            
            # Se a conexão ainda está aberta, o cliente está enviando dados
            if data:
                audio_buffer.write(data)
                
                # O cliente envia a cada 4 segundos. O buffer será processado
                # na próxima rodada, a menos que a lógica de "buffer final" seja ativada.
                
                # ✅ LÓGICA DE PROCESSAMENTO (Exemplo: processar a cada 2 chunks recebidos)
                # Este é um placeholder. O seu cliente envia um chunk com dados de 4s.
                # Como o cliente já está enviando um pacote "pronto para processar",
                # processamos a cada pacote, mas mantendo a lógica de buffer simples.
                
                # 2. RODA O PROCESSAMENTO NO EXECUTOR
                segment_counter += 1
                segment_id = f"seg_{segment_counter}"
                
                # Pega o conteúdo atual do buffer e o reseta
                buffer_content = audio_buffer.getvalue()
                audio_buffer = io.BytesIO()

                # Roda a função síncrona em um thread separado (evita bloqueio do ASGI)
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
        # ✅ CORREÇÃO FINAL: Este é o comportamento esperado quando o cliente fecha.
        # Nenhuma chamada explícita a 'websocket.close()' é necessária aqui.
        print("Cliente desconectado (WebSocketDisconnect). Processando buffer final...")
        
        # 4. PROCESSA O BUFFER FINAL (se houver áudio remanescente)
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
        # 5. TRATAMENTO DE ERRO INESPERADO (e.g., falha no Whisper)
        print(f"ERRO CRÍTICO no WebSocket: {e}")
        # Tenta enviar a mensagem de erro e fechar a conexão de forma limpa
        try:
            await websocket.send_json({"error": f"Erro interno do servidor: {str(e)}", "status": "server_error"})
            # Tentar fechar é necessário em erros inesperados, mas o Uvicorn pode dar o erro ASGI
            # se já estiver em estado de fechamento. Manter o try/except ao redor do close() é a melhor prática.
            await websocket.close() 
        except Exception:
            pass # A conexão já está inativa, ignora a falha de send/close
    
    finally:
        # Garante que o buffer seja limpo e o handler termine.
        audio_buffer.close()
        print("WebSocket handler finished.")
