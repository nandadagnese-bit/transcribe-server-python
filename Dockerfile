# Dockerfile - VERSÃO FINAL OTIMIZADA PARA NUVEM (BLAS/WSS)
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# 1. Instalar dependencias para compilação e runtime
# Inclui libopenblas-dev para otimização BLAS (velocidade)
RUN apt-get update && apt-get install -y \
    build-essential cmake git \
    ffmpeg wget unzip \
    python3 python3-venv python3-pip \
    libsndfile1 libopenblas-dev \
    libopenblas-base \
    && rm -rf /var/lib/apt/lists/*

# 2. Compilar whisper.cpp com otimização BLAS
RUN git clone https://github.com/ggerganov/whisper.cpp /whisper.cpp \
    && cd /whisper.cpp && cmake -B build -DGGML_BLAS=1 \
    && cmake --build build -j

# ⭐️ CORREÇÃO: Definir WORKDIR e copiar o binário BLAS
WORKDIR /app 
RUN cp /whisper.cpp/build/bin/main /app/main-whisper
RUN chmod +x /app/main-whisper

# 3. Instalar dependencias Python (Gunicorn e WebSockets)
COPY requirements.txt /app/
RUN python3 -m pip install --upgrade pip
RUN pip3 install -r requirements.txt gunicorn websockets

# 4. Copia app python e modelo
COPY main.py /app/
RUN mkdir -p /app/models
COPY models/ggml-tiny.bin /app/models/

# 5. Configuração final
EXPOSE 3000

# 6. CMD FINAL CORRIGIDO: Usar Gunicorn com UvicornWorker e flags de proxy WSS
CMD ["gunicorn", "-w", "4", "-k", "uvicorn.workers.UvicornWorker", "main:app", "--bind", "0.0.0.0:3000", "--env", "UVICORN_KWARGS={'proxy_headers': True, 'forwarded_allow_all': True}"]
