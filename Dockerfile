# Dockerfile - Ubuntu + ffmpeg + whisper.cpp + FastAPI
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
  build-essential cmake git libsndfile1 ffmpeg wget unzip python3 python3-venv python3-pip

# Compila whisper.cpp
RUN git clone https://github.com/ggerganov/whisper.cpp /whisper.cpp \
  && cd /whisper.cpp && make -j$(nproc)

# Baixa modelo ggml (opcional: tiny, base, small, medium)
# Substitua "small" por "tiny" ou "base" se preferir.
RUN cd /whisper.cpp && ./models/download-ggml-model.sh small

# App
WORKDIR /app
COPY requirements.txt /app/
RUN python3 -m pip install --upgrade pip
RUN pip3 install -r requirements.txt

COPY main.py /app/

# cria pasta de modelos e copia o modelo baixado do whisper.cpp
RUN mkdir -p /app/models
RUN cp /whisper.cpp/models/ggml-small.bin /app/models/ || true

EXPOSE 3000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "3000"]
