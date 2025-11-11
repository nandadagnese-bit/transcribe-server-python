# Dockerfile - VERSÃO FINAL ESTÁVEL COM WEBSOCKETS (Gunicorn + Uvicorn)
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# 1. Instalar dependencias para compilação e runtime
RUN apt-get update && apt-get install -y \
    build-essential cmake git \
    libsndfile1 ffmpeg wget unzip \
    python3 python3-venv python3-pip \
    libopenblas-dev \
    && rm -rf /var/lib/apt/lists/*

# 2. Compilar whisper.cpp
RUN git clone https://github.com/ggerganov/whisper.cpp /whisper.cpp \
    && cd /whisper.cpp && make -j$(nproc)

# ⭐️ CORREÇÃO CRÍTICA 1: Definir WORKDIR antes de copiar/mover o binário
WORKDIR /app 

# 3. COPIA DO BINÁRIO: Caminho exato confirmado
RUN cp /whisper.cpp/build/bin/main /app/main-whisper
RUN chmod +x /app/main-whisper

# 4. Instalar dependencias Python (incluindo Gunicorn, Uvicorn e WebSockets)
# O Gunicorn precisa ser adicionado no requirements.txt!
COPY requirements.txt /app/
RUN python3 -m pip install --upgrade pip
# O comando abaixo assume que 'websockets' está no requirements.txt, mas forçamos a instalação do gunicorn se você esqueceu.
RUN pip3 install -r requirements.txt gunicorn

# 5. Copia app python e modelo
COPY main.py /app/

# 6. COPIA DO MODELO: ggml-tiny.bin
RUN mkdir -p /app/models
COPY models/ggml-tiny.bin /app/models/

# 7. Expor porta
EXPOSE 3000

# 8. ⭐️ CORREÇÃO CRÍTICA 2 (CMD): Usar Gunicorn com UvicornWorker
# Este comando garante que o Uvicorn rode com múltiplos workers e suporte robusto a WSS/proxy.
CMD ["gunicorn", "-w", "4", "-k", "uvicorn.workers.UvicornWorker", "main:app", "--bind", "0.0.0.0:3000"]
