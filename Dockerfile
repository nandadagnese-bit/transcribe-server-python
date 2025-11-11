# ---------------------------------------------------------
# Dockerfile - SOLUÇÃO FINAL COM ALPINE BUILDER
# Usa Alpine (leve) para compilar e Ubuntu para rodar.
# ---------------------------------------------------------

# --- STAGE 1: COMPILADOR (USANDO ALPINE) ---
FROM alpine:3.18 AS builder
WORKDIR /tmp/build

# 1️⃣ Instalar Ferramentas de Compilação no Alpine
# Dependências do Alpine são diferentes
RUN apk update && apk add \
    build-base \
    git \
    cmake \
    ffmpeg-dev \
    libsndfile-dev \
    openblas-dev \
    # Dependências do Python/FastAPI
    python3 \
    py3-pip \
    && rm -rf /var/cache/apk/*

# 2️⃣ Clonar e Compilar o whisper.cpp com OpenBLAS (Agora no Alpine)
RUN git clone https://github.com/ggerganov/whisper.cpp.git /tmp/whisper

# Compilar com OpenBLAS (usando o 'make' simples no Alpine/musl, que geralmente funciona)
RUN cd /tmp/whisper && \
    make clean && \
    make -j GGML_BLAS=1

# ---------------------------------------------------------

# --- STAGE 2: IMAGEM FINAL DE PRODUÇÃO (VOLTANDO AO UBUNTU) ---
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# 1️⃣ Instalar dependências básicas de runtime do Ubuntu
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    ffmpeg \
    libsndfile1 \
    libopenblas-base \
    && rm -rf /var/lib/apt/lists/*

# 2️⃣ Definir pasta de trabalho
WORKDIR /app

# 3️⃣ COPIAR APENAS O BINÁRIO COMPILADO DO STAGE ANTERIOR (Alpine)
# O binário no Alpine está em /tmp/whisper/main
COPY --from=builder /tmp/whisper/main /app/main-whisper

# 4️⃣ Copiar o restante (código Python, requisitos e modelos)
COPY . /app/
# Garantir permissão de execução
RUN chmod +x /app/main-whisper

# 5️⃣ Instalar dependências do Python
RUN pip3 install --no-cache-dir -r requirements.txt

# 6️⃣ Expor porta padrão do servidor FastAPI
EXPOSE 3000

# 7️⃣ Comando para iniciar o servidor
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "3000"]
