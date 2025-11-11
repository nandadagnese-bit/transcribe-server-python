# ---------------------------------------------------------
# Dockerfile - SOLUÇÃO FINAL (Python Slim + Compilação)
# Usa uma imagem Python otimizada como base
# ---------------------------------------------------------

# --- STAGE 1: COMPILADOR ---
# Usamos a imagem Python slim (Debian-based), mais leve que o Ubuntu, mas mais limpa
FROM python:3.11-slim AS builder
ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /tmp/build

# 1️⃣ Instalar Ferramentas de Build e Dependências
# Instala build-essential, git, cmake e as dependências de whisper/BLAS
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    cmake \
    ffmpeg \
    libsndfile1-dev \
    libopenblas-dev \
    && rm -rf /var/lib/apt/lists/*

# 2️⃣ Clonar e Compilar o whisper.cpp com OpenBLAS (Otimização de CPU)
RUN git clone https://github.com/ggerganov/whisper.cpp.git /tmp/whisper

# Compilar com OpenBLAS ativado
RUN cd /tmp/whisper && \
    cmake -B build -DGGML_BLAS=1 && \
    cmake --build build -j

# ---------------------------------------------------------

# --- STAGE 2: IMAGEM FINAL DE PRODUÇÃO ---
# Voltamos para a mesma imagem para um ambiente de runtime limpo
FROM python:3.11-slim
ENV DEBIAN_FRONTEND=noninteractive

# 1️⃣ Instalar o FFmpeg (Dependência do main.py)
# Note que o FFmpeg não está na imagem slim por padrão
RUN apt-get update && apt-get install -y \
    ffmpeg \
    libsndfile1 \
    libopenblas-base \
    && rm -rf /var/lib/apt/lists/*

# 2️⃣ Definir pasta de trabalho
WORKDIR /app

# 3️⃣ COPIAR APENAS O BINÁRIO COMPILADO DO STAGE ANTERIOR
# O binário no estágio 1 está em /tmp/whisper/build/bin/main
COPY --from=builder /tmp/whisper/build/bin/main /app/main-whisper

# 4️⃣ Copiar o restante do seu diretório local
COPY . /app/
# Garantir permissão de execução
RUN chmod +x /app/main-whisper

# 5️⃣ Instalar dependências do Python
RUN pip install --no-cache-dir -r requirements.txt

# 6️⃣ Expor porta e Iniciar
EXPOSE 3000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "3000"]
