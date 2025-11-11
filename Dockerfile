# ---------------------------------------------------------
# Dockerfile - Versão 3: Compilação Básica (sem BLAS)
# ---------------------------------------------------------

FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# 1️⃣ Instalar dependências básicas + Ferramentas de Compilação
# Removemos o libopenblas-dev
RUN apt-get update && apt-get install -y \
    ffmpeg \
    libsndfile1 \
    python3 \
    python3-pip \
    build-essential \
    git \
    cmake \
    && rm -rf /var/lib/apt/lists/*

# 2️⃣ Definir pasta de trabalho
WORKDIR /app

# 3️⃣ Clonar e Compilar o whisper.cpp na versão padrão
RUN git clone https://github.com/ggerganov/whisper.cpp.git /tmp/whisper

# O erro estava aqui. Vamos tentar o comando 'make' simples, que é o padrão.
RUN cd /tmp/whisper && make clean && make

# Copiar o binário compilado. Se usarmos 'make' puro, o binário vai para /tmp/whisper/main
RUN cp /tmp/whisper/main /app/main-whisper

# 4️⃣ Limpeza (Opcional, mas recomendado)
# Removemos o libopenblas-dev da limpeza também
RUN rm -rf /tmp/whisper && \
    apt-get purge -y git build-essential cmake && \
    apt-get autoremove -y

# 5️⃣ Copiar o restante (código Python e modelos)
COPY . /app/

# 6️⃣ Instalar dependências do Python
RUN pip3 install --no-cache-dir -r requirements.txt

# 7️⃣ Expor porta e Iniciar
EXPOSE 3000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "3000"]
