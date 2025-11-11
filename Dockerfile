# Dockerfile - Ubuntu + ffmpeg + whisper.cpp + Python FastAPI (VERSÃO FUNCIONAL NO DEPLOY, AGORA CORRIGIDA PARA RODAR)
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# 1. Instalar dependencias
RUN apt-get update && apt-get install -y \
    build-essential cmake git libsndfile1 ffmpeg wget unzip python3 python3-venv python3-pip

# 2. Compilar whisper.cpp (O binário 'main' é criado em /whisper.cpp/main)
RUN git clone https://github.com/ggerganov/whisper.cpp /whisper.cpp \
    && cd /whisper.cpp && make -j$(nproc)

# --- CORREÇÕES CRÍTICAS DE CAMINHO ---

# 3. ⭐️ CORREÇÃO 1: COPIAR O BINÁRIO COMPILADO PARA O CAMINHO CORRETO
# O main.py espera /app/main-whisper. Movemos /whisper.cpp/main para lá.
RUN cp /whisper.cpp/main /app/main-whisper
RUN chmod +x /app/main-whisper

# 4. Criar app e instalar dependencias Python
WORKDIR /app
COPY requirements.txt /app/
RUN python3 -m pip install --upgrade pip
RUN pip3 install -r requirements.txt

# 5. Copia app python
COPY main.py /app/

# 6. ⭐️ CORREÇÃO 2: COPIAR O MODELO BINÁRIO (ggml-tiny.bin)
# O main.py espera /app/models/ggml-tiny.bin. 
# Assume que o modelo está no seu diretório local, dentro da pasta 'models/'.
RUN mkdir -p /app/models
COPY models/ggml-tiny.bin /app/models/

# 7. Expor porta
EXPOSE 3000

# 8. Comando default
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "3000"]
