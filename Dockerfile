# Dockerfile - VERSÃO FINAL ESTÁVEL COM WEBSOCKETS (Gunicorn + Uvicorn)
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# 1. Instalar dependencias para compilação (build-essential, cmake, git, etc.)
RUN apt-get update && apt-get install -y \
    build-essential cmake git \
    ffmpeg wget unzip \
    python3 python3-venv python3-pip \
    # Dependências de runtime e compilação do Whisper
    libsndfile1 libopenblas-dev \ 
    libopenblas-base \
    && rm -rf /var/lib/apt/lists/*

# 2. Compilar whisper.cpp
RUN git clone https://github.com/ggerganov/whisper.cpp /whisper.cpp \
    && cd /whisper.cpp && make -j$(nproc)

# ⭐️ CORREÇÃO CRÍTICA 1: Definir WORKDIR antes de copiar/mover o binário
WORKDIR /app 

# 3. COPIA DO BINÁRIO: Caminho exato confirmado
RUN cp /whisper.cpp/build/bin/main /app/main-whisper
RUN chmod +x /app/main-whisper

# 4. Instalar dependencias Python (CORRIGIDA para garantir WEBSOCKETS e Gunicorn)
COPY requirements.txt /app/
RUN python3 -m pip install --upgrade pip
# ✅ CORREÇÃO: Forçamos a instalação de 'websockets' e 'gunicorn' junto com o requirements.txt.
RUN pip3 install -r requirements.txt gunicorn websockets

# 5. Copia app python e modelo
COPY main.py /app/

# 6. COPIA DO MODELO: ggml-tiny.bin
RUN mkdir -p /app/models
COPY models/ggml-tiny.bin /app/models/

# 7. Expor porta
EXPOSE 3000

# 8. CMD FINAL: Usar Gunicorn com UvicornWorker e flags de proxy
CMD ["gunicorn", "-w", "4", "-k", "uvicorn.workers.UvicornWorker", "main:app", "--bind", "0.0.0.0:3000", "--env", "UVICORN_KWARGS={'proxy_headers': True, 'forwarded_allow_all': True}"]
