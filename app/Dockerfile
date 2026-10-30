FROM python:3.12.10-slim
RUN apt-get update && apt-get install -y --no-install-recommends snmp && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY collector.py ./
CMD ["python", "-u", "collector.py"]
