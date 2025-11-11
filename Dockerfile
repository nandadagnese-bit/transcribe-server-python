# ---------------------------------------------------------
# Dockerfile - FastAPI + Whisper.cpp (Render Free)
# ---------------------------------------------------------

FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# 1️⃣ Instalar dependências do sistema
RUN apt-get update && apt-get install -y \
    ffmpeg \
    wget \
    unzip \
    python3 \
    python3-pip \
    libsndfile1

# 2️⃣ Criar pastas
WORKDIR /app
RUN mkdir -p /whisper.cpp /app/models

# 3️⃣ Baixar Whisper.cpp binário pronto (Linux 64 bits)
RUN cd /whisper.cpp \
    && wget https://github.com/ggerganov/whisper.cpp/releases/latest/download/whisper-bin-x64.zip -O whisper.zip \
    && unzip whisper.zip \
    && mv main /app/main-whisper \
    && chmod +x /app/main-whisper \
    && ls -l /app/main-whisper

# 4️⃣ Baixar modelo "tiny" (leve e rápido)
RUN wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin -O /app/models/ggml-tiny.bin

# 5️⃣ Instalar dependências Python
COPY requirements.txt /app/
RUN python3 -m pip install --upgrade pip
RUN pip3 install -r requirements.txt

# 6️⃣ Copiar código do servidor
COPY main.py /app/

# 7️⃣ Expor porta e iniciar o servidor FastAPI
EXPOSE 3000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "3000"]
