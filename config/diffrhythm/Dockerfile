# =============================================================================
# DiffRhythm - AI Music Generation with Latent Diffusion
# =============================================================================
# Builds DiffRhythm with Gradio interface for web-based music generation
# Requires NVIDIA GPU with 8GB+ VRAM
# Based on official DiffRhythm Docker configuration
# =============================================================================

FROM nvidia/cuda:12.1-cudnn8-runtime-ubuntu22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV GRADIO_SERVER_NAME=0.0.0.0
ENV GRADIO_SERVER_PORT=7860

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    python3.10-venv \
    git \
    git-lfs \
    espeak-ng \
    ffmpeg \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set Python 3.10 as default
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.10 1 \
    && update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 1

# Set working directory
WORKDIR /app

# Clone DiffRhythm repository
RUN git clone https://github.com/ASLP-lab/DiffRhythm.git . \
    && git lfs install \
    && git lfs pull

# Install Python dependencies
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir \
    torch==2.1.0 \
    torchaudio==2.1.0 \
    --index-url https://download.pytorch.org/whl/cu121

# Install project requirements
RUN pip install --no-cache-dir -r requirements.txt

# Install Gradio for web interface
RUN pip install --no-cache-dir gradio>=4.0.0

# Set environment variables for eSpeak
ENV PHONEMIZER_ESPEAK_LIBRARY=/usr/lib/x86_64-linux-gnu/libespeak-ng.so.1
ENV PHONEMIZER_ESPEAK_PATH=/usr/bin

# Create directories for models and output
RUN mkdir -p /app/models /app/output /app/input

# Expose Gradio port
EXPOSE 7860

# Create entrypoint script for Gradio interface
RUN echo '#!/bin/bash\n\
cd /app\n\
python -c "\n\
import gradio as gr\n\
import subprocess\n\
import os\n\
\n\
def generate_music(lyrics, style_prompt, duration, use_chunked):\n\
    \"\"\"Generate music using DiffRhythm\"\"\"\n\
    try:\n\
        # Save inputs to files\n\
        with open(\"/app/input/lyrics.txt\", \"w\") as f:\n\
            f.write(lyrics)\n\
        \n\
        # Build command\n\
        cmd = [\n\
            \"python\", \"infer/infer.py\",\n\
            \"--lrc_path\", \"/app/input/lyrics.txt\",\n\
            \"--ref_prompt\", style_prompt,\n\
            \"--output_dir\", \"/app/output\",\n\
        ]\n\
        \n\
        if use_chunked:\n\
            cmd.append(\"--chunked\")\n\
        \n\
        result = subprocess.run(cmd, capture_output=True, text=True, cwd=\"/app\")\n\
        \n\
        # Find the latest output file\n\
        output_files = sorted([f for f in os.listdir(\"/app/output\") if f.endswith(\".wav\")])\n\
        if output_files:\n\
            return f\"/app/output/{output_files[-1]}\", result.stdout\n\
        return None, f\"Error: {result.stderr}\"\n\
    except Exception as e:\n\
        return None, str(e)\n\
\n\
# Create Gradio interface\n\
with gr.Blocks(title=\"DiffRhythm - AI Music Generation\") as demo:\n\
    gr.Markdown(\"# 🎵 DiffRhythm - AI Music Generation\")\n\
    gr.Markdown(\"Generate full-length songs from lyrics and style prompts using latent diffusion.\")\n\
    \n\
    with gr.Row():\n\
        with gr.Column():\n\
            lyrics = gr.Textbox(\n\
                label=\"Lyrics (LRC format or plain text)\",\n\
                placeholder=\"[00:00.00] First line...\\n[00:05.00] Second line...\",\n\
                lines=10\n\
            )\n\
            style = gr.Textbox(\n\
                label=\"Style Prompt\",\n\
                placeholder=\"Pop, upbeat, female vocals, acoustic guitar\",\n\
                value=\"Pop Emotional Piano\"\n\
            )\n\
            chunked = gr.Checkbox(label=\"Use chunked mode (saves VRAM)\", value=True)\n\
            generate_btn = gr.Button(\"Generate Music\", variant=\"primary\")\n\
        \n\
        with gr.Column():\n\
            audio_output = gr.Audio(label=\"Generated Music\", type=\"filepath\")\n\
            log_output = gr.Textbox(label=\"Generation Log\", lines=5)\n\
    \n\
    generate_btn.click(\n\
        fn=generate_music,\n\
        inputs=[lyrics, style, gr.Number(visible=False, value=95), chunked],\n\
        outputs=[audio_output, log_output]\n\
    )\n\
\n\
demo.launch(server_name=\"0.0.0.0\", server_port=7860, share=False)\n\
"\n\
' > /app/start.sh && chmod +x /app/start.sh

# Default command
CMD ["/bin/bash", "/app/start.sh"]
