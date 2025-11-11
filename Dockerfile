# Dockerfile - VERSÃO FINAL PARA FASTAPI COM WEBSOCKETS E WHISPER
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

# ⭐️ CORREÇÃO CRÍTICA: Definir WORKDIR antes de copiar/mover
WORKDIR /app 

# 3. ⭐️ COPIA DO BINÁRIO: Caminho exato confirmado
RUN cp /whisper.cpp/build/bin/main /app/main-whisper
RUN chmod +x /app/main-whisper

# 4. Instalar dependencias Python
COPY requirements.txt /app/
RUN python3 -m pip install --upgrade pip
# Necessário instalar 'websockets' se você não o colocou no requirements.txt
RUN pip3 install -r requirements.txt websockets

# 5. Copia app python e modelo
COPY main.py /app/

# 6. COPIA DO MODELO: ggml-tiny.bin
RUN mkdir -p /app/models
COPY models/ggml-tiny.bin /app/models/

# 7. Expor porta
EXPOSE 3000

# 8. Comando default (Uvicorn)
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "3000"]
