FROM mcr.microsoft.com/devcontainers/python:1-3.12-bookworm

WORKDIR /app
COPY server.py /app/server.py

ENV PYTHONUNBUFFERED=1
EXPOSE 8080

CMD ["python", "/app/server.py"]
