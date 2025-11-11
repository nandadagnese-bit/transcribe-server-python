# Dockerfile - VERSÃO FINAL E CORRIGIDA (Ordem dos Comandos)
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# 1. Instalar dependencias
RUN apt-get update && apt-get install -y \
    build-essential cmake git libsndfile1 ffmpeg wget unzip python3 python3-venv python3-pip \
    && rm -rf /var/lib/apt/lists/*

# 2. Compilar whisper.cpp
RUN git clone https://github.com/ggerganov/whisper.cpp /whisper.cpp \
    && cd /whisper.cpp && make -j$(nproc)

# ⭐️ CORREÇÃO DA ORDEM: DEFINIR O DIRETÓRIO DE TRABALHO AGORA
# Criamos a pasta /app para que o cp e os próximos comandos possam usá-la.
WORKDIR /app 

# --- COPIAR O BINÁRIO ---

# 3. COPIA DO BINÁRIO: Caminho exato confirmado!
RUN cp /whisper.cpp/build/bin/main /app/main-whisper
RUN chmod +x /app/main-whisper

# 4. Criar app e instalar dependencias Python
# A pasta /app já existe agora, então o COPY pode ser feito.
COPY requirements.txt /app/
RUN python3 -m pip install --upgrade pip
RUN pip3 install -r requirements.txt

# 5. Copia app python
COPY main.py /app/

# 6. COPIA DO MODELO: ggml-tiny.bin
RUN mkdir -p /app/models
COPY models/ggml-tiny.bin /app/models/

# 7. Expor porta
EXPOSE 3000

# 8. Comando default
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "3000"]
