# Dockerfile TEMPORÁRIO DE DIAGNÓSTICO
FROM ubuntu:22.04

# 1. Instalar dependencias necessárias para a compilação
RUN apt-get update && apt-get install -y \
    build-essential cmake git \
    && rm -rf /var/lib/apt/lists/*

# 2. Compilar whisper.cpp (O passo que funciona)
RUN git clone https://github.com/ggerganov/whisper.cpp /whisper.cpp \
    && cd /whisper.cpp && make -j$(nproc)

# 3. COMANDO DE DIAGNÓSTICO: Parar aqui e listar os arquivos
# Este comando lista todos os arquivos que se chamam 'main' no repositório clonado
RUN find /whisper.cpp -name "main"
