# Dockerfile - Ubuntu + ffmpeg + whisper.cpp + Python FastAPI
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# instalar dependencias
RUN apt-get update && apt-get install -y \
  build-essential cmake git libsndfile1 ffmpeg wget unzip python3 python3-venv python3-pip

# compilar whisper.cpp
RUN git clone https://github.com/ggerganov/whisper.cpp /whisper.cpp \
  && cd /whisper.cpp && make -j$(nproc)

# criar app
WORKDIR /app
COPY requirements.txt /app/
RUN python3 -m pip install --upgrade pip
RUN pip3 install -r requirements.txt

# copia app python
COPY main.py /app/

# criar pasta para modelos
RUN mkdir -p /app/models

# expor porta
EXPOSE 3000

# comando default
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "3000"]
