# ---------------------------------------------------------
# Dockerfile - Servidor FastAPI + Whisper.cpp (pré-compilado)
# ---------------------------------------------------------

FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# 1️⃣ Instalar dependências do sistema
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    libsndfile1 \
    libsndfile1-dev \
    ffmpeg \
    wget \
    unzip \
    python3 \
    python3-venv \
    python3-pip

# 2️⃣ Baixar o whisper.cpp já compilado (binário pronto)
RUN mkdir -p /whisper.cpp && cd /whisper.cpp \
    && wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/whisper-linux-x64.zip -O whisper.zip \
    && unzip whisper.zip \
    && chmod +x /whisper.cpp/main \
    && ls -l /whisper.cpp/main

# 3️⃣ Baixar o modelo "tiny" (leve e rápido)
RUN cd /whisper.cpp && mkdir -p models \
    && wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin -O ./models/ggml-tiny.bin

# 4️⃣ Configurar ambiente Python e dependências
WORKDIR /app
COPY requirements.txt /app/
RUN python3 -m pip install --upgrade pip
RUN pip3 install -r requirements.txt

# 5️⃣ Copiar o código principal
COPY main.py /app/

# 6️⃣ Copiar o modelo e o executável para a aplicação
RUN mkdir -p /app/models
RUN cp /whisper.cpp/models/ggml-tiny.bin /app/models/
RUN cp /whisper.cpp/main /app/main-whisper

# 7️⃣ Expor porta e iniciar servidor FastAPI
EXPOSE 3000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "3000"]
