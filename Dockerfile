# ---------------------------------------------------------
# Dockerfile - Servidor FastAPI + Whisper.cpp no Render
# ---------------------------------------------------------

# 1️⃣ Imagem base do Ubuntu
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# 2️⃣ Instalar dependências do sistema
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    libsndfile1 \
    ffmpeg \
    wget \
    unzip \
    python3 \
    python3-venv \
    python3-pip

# 3️⃣ Baixar e compilar o whisper.cpp
RUN git clone https://github.com/ggerganov/whisper.cpp /whisper.cpp \
    && cd /whisper.cpp && make -j1 \
    && ls -l /whisper.cpp/main


# 4️⃣ Baixar o modelo "small" (pode trocar por tiny/base/medium)
RUN cd /whisper.cpp && ./models/download-ggml-model.sh small

# 5️⃣ Configurar ambiente Python e dependências
WORKDIR /app
COPY requirements.txt /app/
RUN python3 -m pip install --upgrade pip
RUN pip3 install -r requirements.txt

# 6️⃣ Copiar o código principal
COPY main.py /app/

# 7️⃣ Copiar o modelo E O EXECUTÁVEL para a pasta da aplicação
RUN mkdir -p /app/models
RUN cp /whisper.cpp/models/ggml-small.bin /app/models/ || true
# ✅ ESTA É A NOVA LINHA:
RUN cp /whisper.cpp/main /app/main-whisper || true

# 8️⃣ Expor porta e iniciar FastAPI
EXPOSE 3000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "3000"]

