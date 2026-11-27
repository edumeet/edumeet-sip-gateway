# The build context is deploy/proxyAPI of SIPMediaGW with this directory copied into it
# (build_and_publish.sh on the build machine).
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --root-user-action=ignore -r /tmp/requirements.txt && rm /tmp/requirements.txt
COPY . /app
CMD ["uvicorn", "proxy:app", "--host", "0.0.0.0", "--port", "80"]
