# ---------------------------------------------------------
# Dockerfile - SOLUÇÃO FINAL COM DEBIAN SLIM
# Retorna à compilação simples 'make' no ambiente Debian Slim.
# ---------------------------------------------------------

# --- STAGE 1: COMPILADOR ---
FROM python:3.11-slim AS builder
ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /tmp/build

# 1️⃣ Instalar Ferramentas de Build e Dependências
# Instala build-essential, git, cmake e as dependências essenciais (libsndfile-dev, g++)
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    cmake \
    g++ \
    libsndfile1-dev \
    libopenblas-dev \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# 2️⃣ Clonar e Compilar o whisper.cpp
# Usaremos o comando 'make' padrão (sem BLAS flag no comando) para garantir a estabilidade
RUN git clone https://github.com/ggerganov/whisper.cpp.git /tmp/whisper

# Compilação simples: o 'make' sem cmake é muitas vezes mais estável
RUN cd /tmp/whisper && \
    make clean && \
    make -j

# ---------------------------------------------------------

# --- STAGE 2: IMAGEM FINAL DE PRODUÇÃO ---
FROM python:3.11-slim
ENV DEBIAN_FRONTEND=noninteractive

# 1️⃣ Instalar o FFmpeg e libs de runtime
RUN apt-get update && apt-get install -y \
    ffmpeg \
    libsndfile1 \
    libopenblas-base \
    && rm -rf /var/lib/apt/lists/*

# 2️⃣ Definir pasta de trabalho
WORKDIR /app

# 3️⃣ COPIAR APENAS O BINÁRIO COMPILADO DO STAGE ANTERIOR
# Se 'make' for usado, o binário está em /tmp/whisper/main
COPY --from=builder /tmp/whisper/main /app/main-whisper

# 4️⃣ Copiar o restante do seu diretório local
COPY . /app/
# Garantir permissão de execução
RUN chmod +x /app/main-whisper

# 5️⃣ Instalar dependências do Python
RUN pip install --no-cache-dir -r requirements.txt

# 6️⃣ Expor porta e Iniciar
EXPOSE 3000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "3000"]
