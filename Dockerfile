# ---------------------------------------------------------
# Dockerfile - Servidor FastAPI + Whisper.cpp pré-instalado
# ---------------------------------------------------------

FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# 1️⃣ Instalar dependências básicas
RUN apt-get update && apt-get install -y \
    ffmpeg \
    libsndfile1 \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# 2️⃣ Definir pasta de trabalho
WORKDIR /app

# 3️⃣ Copiar tudo do repositório (inclusive o modelo e o binário)
COPY . /app/

# 4️⃣ Garantir permissão de execução para o binário
RUN chmod +x /app/main-whisper

# 5️⃣ Instalar dependências do Python
RUN pip3 install --no-cache-dir -r requirements.txt

# 6️⃣ Expor porta padrão
EXPOSE 3000

# 7️⃣ Comando para iniciar o servidor
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "3000"]
