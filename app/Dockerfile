FROM python:3.10-alpine

WORKDIR /app
COPY . .
RUN pip install --no-cache-dir -r requirements.txt
EXPOSE 5000

CMD ["python", "wsgi.py"]