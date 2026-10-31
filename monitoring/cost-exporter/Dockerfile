FROM python:3.12-slim
WORKDIR /app
COPY exporter.py /app/exporter.py
USER 65534:65534
EXPOSE 9400
CMD ["python", "/app/exporter.py"]
