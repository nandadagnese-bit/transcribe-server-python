# ---------------------------------------------------------
# Dockerfile - Servidor FastAPI + Whisper.cpp COMPILADO
# ---------------------------------------------------------

FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# 1️⃣ Instalar dependências básicas + Ferramentas de Compilação
# libopenblas-dev: Garante que o OpenBLAS (para otimização de CPU) esteja instalado
RUN apt-get update && apt-get install -y \
    ffmpeg \
    libsndfile1 \
    python3 \
    python3-pip \
    build-essential \
    git \
    cmake \
    libopenblas-dev \
    && rm -rf /var/lib/apt/lists/*

# 2️⃣ Definir pasta de trabalho
WORKDIR /app

# 3️⃣ Clonar e Compilar o whisper.cpp com OpenBLAS
RUN git clone https://github.com/ggerganov/whisper.cpp.git /tmp/whisper

# Entrar na pasta, criar o build e compilar.
# -DGGML_BLAS=1 habilita o uso do OpenBLAS.
RUN cd /tmp/whisper && \
    cmake -B build -DGGML_BLAS=1 && \
    cmake --build build -j

# COPIAR O BINÁRIO: O binário compilado chama-se 'main' e estará em 'build/bin/main'.
# Copiamos ele para /app com o nome esperado: 'main-whisper'
RUN cp /tmp/whisper/build/bin/main /app/main-whisper

# 4️⃣ Limpeza (Opcional, mas recomendado para reduzir o tamanho da imagem)
RUN rm -rf /tmp/whisper && \
    apt-get purge -y git build-essential cmake libopenblas-dev && \
    apt-get autoremove -y

# 5️⃣ Copiar resto do repositório (código Python e modelos)
COPY . /app/

# 6️⃣ Instalar dependências do Python
# Certifique-se de que o uvicorn esteja no seu requirements.txt
RUN pip3 install --no-cache-dir -r requirements.txt

# 7️⃣ Expor porta e Iniciar
EXPOSE 3000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "3000"]
